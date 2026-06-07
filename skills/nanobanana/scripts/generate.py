#!/usr/bin/env python3
"""
Nano Banana CLI generator.
Usage:
    python generate.py --prompt "..." --aspect 16:9 --model flash --out path.png
    python generate.py --prompt "..." --ref image1.png --ref image2.png --out path.png
"""
import argparse
import os
import sys
from io import BytesIO
from pathlib import Path

MODELS = {
    "flash": "gemini-2.5-flash-image",
    "flash3": "gemini-3.1-flash-image-preview",
    "pro": "gemini-3-pro-image-preview",
}


def yaml_value(path, key):
    try:
        with path.open("r", encoding="utf-8") as handle:
            for raw_line in handle:
                line = raw_line.rstrip("\r\n").lstrip()
                if not line.startswith(f"{key}:"):
                    continue
                value = line.split(":", 1)[1].strip()
                if " #" in value:
                    value = value.split(" #", 1)[0].rstrip()
                return value
    except OSError:
        return ""
    return ""


def image_generation_uses_gemini(value):
    return "gemini" in {route.strip() for route in value.split(",")}


def capabilities_file():
    configured = os.environ.get("WALTER_AI_CAPABILITIES_FILE")
    if configured:
        return Path(configured).expanduser()
    config_dir = os.environ.get("WALTER_CONFIG", "~/.config/walter-os")
    return Path(config_dir).expanduser() / "ai-capabilities.yaml"


def validate_gemini_capability():
    path = capabilities_file()
    if not path.exists():
        return

    provider_gemini = yaml_value(path, "provider_gemini")
    if provider_gemini == "disabled":
        print(
            f"nanobanana: provider_gemini is disabled in {path}. "
            "Run `walter ai configure --set image_generation=gemini` or choose another image workflow.",
            file=sys.stderr,
        )
        sys.exit(3)

    route_image_generation = yaml_value(path, "route_image_generation")
    if route_image_generation and not image_generation_uses_gemini(route_image_generation):
        print(
            f"nanobanana: route_image_generation must include gemini in {path}.",
            file=sys.stderr,
        )
        sys.exit(3)


def import_deps():
    try:
        from google import genai
        from PIL import Image
    except ImportError:
        print("Missing deps. Install: pip install google-genai pillow", file=sys.stderr)
        sys.exit(1)
    return genai, Image


def main():
    parser = argparse.ArgumentParser(description="Nano Banana image generator")
    parser.add_argument("--prompt", required=True, help="Text prompt")
    parser.add_argument("--out", required=True, help="Output PNG path")
    parser.add_argument("--model", default="flash3", choices=list(MODELS),
                        help="flash=2.5, flash3=3.1 preview, pro=3 pro preview")
    parser.add_argument("--aspect", default="1:1",
                        choices=["1:1", "4:3", "3:4", "16:9", "9:16",
                                 "21:9", "5:4", "4:5", "3:2", "2:3"])
    parser.add_argument("--ref", action="append", default=[],
                        help="Reference image path (repeatable, up to 10)")
    args = parser.parse_args()

    validate_gemini_capability()

    if not os.environ.get("GEMINI_API_KEY"):
        print("Set GEMINI_API_KEY in env (https://aistudio.google.com/apikey)",
              file=sys.stderr)
        sys.exit(1)

    genai, Image = import_deps()

    client = genai.Client()
    contents = [args.prompt]
    for ref_path in args.ref:
        contents.append(Image.open(ref_path))

    response = client.models.generate_content(
        model=MODELS[args.model],
        contents=contents,
        config={"image_config": {"aspect_ratio": args.aspect}},
    )

    out_path = Path(args.out)
    out_path.parent.mkdir(parents=True, exist_ok=True)

    saved = False
    for part in response.candidates[0].content.parts:
        if getattr(part, "inline_data", None):
            Image.open(BytesIO(part.inline_data.data)).save(out_path)
            saved = True
            break

    if not saved:
        # Likely a safety block or text-only response.
        for part in response.candidates[0].content.parts:
            if getattr(part, "text", None):
                print(part.text, file=sys.stderr)
        sys.exit(2)

    # Sidecar prompt file for reproducibility
    sidecar = out_path.with_suffix(".prompt.txt")
    sidecar.write_text(
        f"model: {MODELS[args.model]}\n"
        f"aspect: {args.aspect}\n"
        f"refs: {args.ref}\n"
        f"prompt:\n{args.prompt}\n"
    )

    print(f"Wrote {out_path}")
    print(f"Sidecar: {sidecar}")


if __name__ == "__main__":
    main()
