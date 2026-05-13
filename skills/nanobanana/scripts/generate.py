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

try:
    from google import genai
    from PIL import Image
except ImportError:
    print("Missing deps. Install: pip install google-genai pillow", file=sys.stderr)
    sys.exit(1)

MODELS = {
    "flash": "gemini-2.5-flash-image",
    "flash3": "gemini-3.1-flash-image-preview",
    "pro": "gemini-3-pro-image-preview",
}


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

    if not os.environ.get("GEMINI_API_KEY"):
        print("Set GEMINI_API_KEY in env (https://aistudio.google.com/apikey)",
              file=sys.stderr)
        sys.exit(1)

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
