import argparse
import json
import os
from datetime import datetime
from zoneinfo import ZoneInfo

from app.ai.agenda import PARSER_MODEL, PARSER_REGION, bedrock_client, parse_agenda_with_telemetry


def _parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description="Exercise the Peach Nova agenda parser")
    subparsers = parser.add_subparsers(dest="command", required=True)
    subparsers.add_parser("hello", help="Send a minimal Bedrock Converse request")
    parse = subparsers.add_parser("parse", help="Parse agenda text")
    parse.add_argument("--text", required=True)
    parse.add_argument("--tz", default=os.getenv("TZ", "Europe/Kyiv"))
    return parser


def main() -> None:
    args = _parser().parse_args()
    model = os.getenv("PARSER_MODEL", PARSER_MODEL)
    client = bedrock_client(region=os.getenv("AWS_REGION", PARSER_REGION))
    if args.command == "hello":
        response = client.converse(
            modelId=model,
            messages=[{"role": "user", "content": [{"text": "Reply with hello."}]}],
            inferenceConfig={"maxTokens": 16, "temperature": 0},
        )
        print(
            json.dumps({"stopReason": response.get("stopReason"), "usage": response.get("usage")})
        )
        return

    now = datetime.now(ZoneInfo(args.tz))
    result = parse_agenda_with_telemetry(args.text, now.date(), args.tz, client=client, model=model)
    print(result.model_dump_json(indent=2))


if __name__ == "__main__":
    main()
