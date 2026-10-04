#!/usr/bin/env python3
import base64
import json
import os
import subprocess
import sys
import tempfile
import time
import urllib.error
import urllib.parse
import urllib.request


def required_environment(name):
    value = os.environ.get(name)
    if not value:
        raise SystemExit(f"Missing environment variable: {name}")
    return value


def base64url(value):
    return base64.urlsafe_b64encode(value).rstrip(b"=").decode("ascii")


def read_der_length(data, offset):
    first = data[offset]
    offset += 1
    if first < 0x80:
        return first, offset
    byte_count = first & 0x7F
    return int.from_bytes(data[offset:offset + byte_count], "big"), offset + byte_count


def der_signature_to_raw(signature):
    if not signature or signature[0] != 0x30:
        raise ValueError("Expected an ECDSA DER sequence")
    sequence_length, offset = read_der_length(signature, 1)
    sequence_end = offset + sequence_length
    values = []
    while offset < sequence_end:
        if signature[offset] != 0x02:
            raise ValueError("Expected an ECDSA DER integer")
        integer_length, offset = read_der_length(signature, offset + 1)
        integer = signature[offset:offset + integer_length].lstrip(b"\0")
        if len(integer) > 32:
            raise ValueError("ECDSA integer exceeds P-256 width")
        values.append(integer.rjust(32, b"\0"))
        offset += integer_length
    if len(values) != 2 or offset != sequence_end:
        raise ValueError("Invalid ECDSA DER signature")
    return b"".join(values)


def create_jwt(private_key, key_id, issuer_id):
    issued_at = int(time.time())
    header = base64url(json.dumps(
        {"alg": "ES256", "kid": key_id, "typ": "JWT"}, separators=(",", ":")
    ).encode())
    payload = base64url(json.dumps({
        "iss": issuer_id,
        "iat": issued_at,
        "exp": issued_at + 15 * 60,
        "aud": "appstoreconnect-v1",
    }, separators=(",", ":")).encode())
    signing_input = f"{header}.{payload}".encode("ascii")

    key_path = None
    try:
        with tempfile.NamedTemporaryFile(mode="w", encoding="utf-8", delete=False) as key_file:
            key_file.write(private_key)
            key_path = key_file.name
        signature = subprocess.run(
            ["openssl", "dgst", "-sha256", "-sign", key_path],
            input=signing_input,
            check=True,
            capture_output=True,
        ).stdout
    finally:
        if key_path:
            os.remove(key_path)

    return f"{signing_input.decode('ascii')}.{base64url(der_signature_to_raw(signature))}"


def get_json(url, token):
    request = urllib.request.Request(url, headers={"Authorization": f"Bearer {token}"})
    try:
        with urllib.request.urlopen(request, timeout=30) as response:
            return json.load(response)
    except urllib.error.HTTPError as error:
        body = error.read().decode("utf-8", errors="replace")
        raise SystemExit(f"App Store Connect request failed ({error.code}): {body}") from error


def query_url(path, parameters):
    return "https://api.appstoreconnect.apple.com" + path + "?" + urllib.parse.urlencode(parameters)


def parse_build_number(number):
    parts = number.split(".")
    if not parts or not all(part.isdigit() for part in parts):
        return None
    return tuple(int(part) for part in parts)


def valid_build_number(number):
    parts = parse_build_number(number)
    return parts is not None and 1 <= len(parts) <= 3 and parts[0] > 0


def main():
    bundle_id = required_environment("BUNDLE_ID")
    tested_build = required_environment("TESTED_BUILD_NUMBER")
    production_build = required_environment("PRODUCTION_BUILD_NUMBER")
    if not valid_build_number(production_build):
        raise SystemExit("Production build must contain one to three period-separated integers.")
    token = create_jwt(
        required_environment("ASC_PRIVATE_KEY"),
        required_environment("ASC_KEY_ID"),
        required_environment("ASC_ISSUER_ID"),
    )

    apps = get_json(query_url("/v1/apps", {
        "filter[bundleId]": bundle_id,
        "limit": 2,
    }), token)["data"]
    if not apps:
        raise SystemExit(f"No App Store Connect app found for {bundle_id}")
    if len(apps) > 1:
        raise SystemExit(f"Multiple App Store Connect apps found for {bundle_id}")

    app_id = apps[0]["id"]
    url = query_url(f"/v1/apps/{app_id}/builds", {
        "fields[builds]": "version",
        "limit": 200,
    })
    build_numbers = []
    while url:
        response = get_json(url, token)
        build_numbers.extend(build["attributes"]["version"] for build in response["data"])
        url = response.get("links", {}).get("next")

    if tested_build not in build_numbers:
        raise SystemExit(f"TestFlight build {tested_build} was not found for {bundle_id}")
    if production_build in build_numbers:
        raise SystemExit(f"Production build {production_build} is already used for {bundle_id}")

    numeric = [number for number in build_numbers if parse_build_number(number) is not None]
    latest = max(numeric, key=parse_build_number) if numeric else "none"
    print(f"Verified tested build {tested_build}; latest App Store Connect build is {latest}.", file=sys.stderr)
    print(production_build)


if __name__ == "__main__":
    main()
