---
name: nanobanana
description: Generate or edit images using Google's Nano Banana family (Gemini 2.5 Flash Image, Gemini 3.1 Flash Image Preview, and Gemini 3 Pro Image Preview). Use this skill whenever the user asks to "generate an image", "create a visual", "make a hero image", "edit this photo", "blend these references", produce assets for blog posts, social media, marketing/DevRel content, icons, infographics, magazine-style mocks, isometric scenes, or product mockups, OR when the user mentions "nano banana", "Gemini image", "nanobanana", "Imagen alternative", "Google image gen". Trigger this skill even when the request is casual ("hazme una imagen de X", "necesito un visual para el blog post"). Always prefer this over describing an image in text when a real image is what the user wants.
---

# Nano Banana — Image Generation & Editing

Google's Nano Banana family lives in the Gemini API. Three tiers as of May 2026:

| Variant | Model ID | Use when |
|---|---|---|
| Nano Banana | `gemini-2.5-flash-image` | Speed, cost (~$0.039/img), high-volume batches, drafts, DevRel iteration |
| Nano Banana 2 | `gemini-3.1-flash-image-preview` | Default for production: better text rendering, hybrid reasoning |
| Nano Banana Pro | `gemini-3-pro-image-preview` | 4K output, complex semantic reasoning, hero/marketing assets, multi-language text in image |

All outputs include an invisible **SynthID watermark**. Decline requests to remove it.

## Setup (once)

```bash
pip install google-genai pillow
export GEMINI_API_KEY="..."   # https://aistudio.google.com/apikey
```

For the dotai repo, store the key in `~/.config/dotai/secrets.env` (gitignored), sourced by your shell.

## 1. Text → Image (basic generation)

```python
from google import genai
from PIL import Image
from io import BytesIO

client = genai.Client()

response = client.models.generate_content(
    model="gemini-2.5-flash-image",
    contents=[
        "Hero illustration for a Solana RPC infrastructure blog post. "
        "Isometric 45° view of a glowing data pipeline made of hexagonal nodes, "
        "electric purple and warm amber accents, soft solid cream background, "
        "PBR materials, gentle rim lighting from upper-left."
    ],
    config={"image_config": {"aspect_ratio": "16:9"}},
)

for part in response.candidates[0].content.parts:
    if part.inline_data is not None:
        Image.open(BytesIO(part.inline_data.data)).save("hero.png")
```

Supported aspect ratios: `1:1`, `4:3`, `3:4`, `16:9`, `9:16`, `21:9`, `5:4`, `4:5`, `3:2`, `2:3`.

## 2. Image + Prompt → Edit (targeted transformation)

Pass the existing image alongside the prompt. The model preserves identity, lighting, and unchanged regions.

```python
input_img = Image.open("draft.png")

response = client.models.generate_content(
    model="gemini-2.5-flash-image",
    contents=[
        "Remove the laptop on the desk. Keep everything else identical, "
        "including lighting, shadows, and the coffee cup.",
        input_img,
    ],
)
```

Common edit prompts that work well:
- "Remove [object]. Preserve everything else."
- "Change the background to [description]. Keep the subject pixel-identical."
- "Re-light the scene as golden hour from the left. Same composition."
- "Convert to [style] while preserving facial features and pose."

## 3. Multi-image blend / reference (up to 8–10 images)

For brand-consistent assets — placing logos, building product mockups, propagating a style across variants.

```python
logo = Image.open("[company]-logo.png")
device = Image.open("laptop-mockup.png")

response = client.models.generate_content(
    model="gemini-3-pro-image-preview",   # Pro for fidelity on real products
    contents=[
        "Place the logo on the laptop screen, perspective-corrected and "
        "color-graded to match the scene. Photorealistic.",
        logo,
        device,
    ],
)
```

## 4. Multi-turn iteration (character/product consistency)

Pass the previous output back as input on the next turn — the model retains identity across iterations. Costs less than regenerating from scratch and avoids drift.

```python
turn1 = client.models.generate_content(
    model="gemini-3.1-flash-image-preview",
    contents=["A friendly otter mascot for a dev tool, flat illustration, holding a wrench"],
)
otter = extract_image(turn1)

turn2 = client.models.generate_content(
    model="gemini-3.1-flash-image-preview",
    contents=["Same otter, now waving from a laptop screen", otter],
)
```

## 5. Text inside images

The Pro tier renders typography reliably. Always quote the exact string you want:

> "A glossy magazine cover. The cover has the large bold words '[Company]' in a serif font filling the upper third. Issue number '01' and 'May 2026' in the bottom-right corner."

Avoid: "magazine cover with the company name on it" — the model has to guess the string.

## Prompting principles that actually move the needle

1. **Describe physics, not vibes.** "Warm rim light from window left, soft falloff, 30° shadow angle" beats "nice lighting".
2. **Use reference images for brand/identity.** Don't describe a logo in words — pass the file.
3. **Iterate conversationally.** Single-shot regenerations lose identity. Multi-turn edits preserve it and cost less.
4. **Name materials explicitly.** "Brushed aluminum", "matte rubber", "subsurface scattering on skin" — the model reads PBR vocabulary.
5. **Compose like a photographer.** Specify camera distance, focal length feel ("looks like 35mm"), depth of field.
6. **For DevRel/blog hero assets:** "isometric 45°", "PBR materials", "soft solid background", "no text" (unless you want text), "minimalist composition".

## Cost & latency

- **2.5 Flash Image**: ~$0.039/image, sub-2s latency. Use for drafts, A/B testing prompts, batch generation.
- **3.1 Flash Image Preview**: similar economics, hybrid reasoning toggle. Default production tier.
- **3 Pro Image Preview**: higher cost, 64K input / 32K output context, 4K output. Use for hero shots and final marketing assets only.

When iterating, draft with Flash and only escalate to Pro for the final pass.

## When NOT to use this skill

- **Real public figures**: don't generate; use stock or licensed imagery.
- **Precise diagrams / architecture**: use Mermaid, Excalidraw, or hand-drawn — generative models hallucinate connections.
- **Legal/identity contexts**: court evidence, ID photos, anything where authenticity matters.
- **Code-style screenshots**: use real screenshots from a real terminal/IDE.
- **Charts with real data**: use a charting library; do not invent visual data.

## Output convention for this codebase

Save generated assets to `assets/generated/<YYYY-MM-DD>/<short-slug>.png`. Always commit a sidecar `<short-slug>.prompt.txt` with the exact prompt used, so the asset is reproducible. Example:

```
assets/generated/2026-05-02/
├── yellowstone-hero.png
└── yellowstone-hero.prompt.txt
```

## Helper script (optional)

A reusable wrapper lives at `scripts/generate.py` in this skill directory. Use it for one-off CLI generation:

```bash
python scripts/generate.py \
  --prompt "Isometric Solana validator network, electric purple, cream background" \
  --aspect 16:9 \
  --model flash \
  --out assets/generated/2026-05-02/validators.png
```

The script handles the SDK boilerplate, writes the sidecar prompt file, and exits non-zero on safety blocks so it composes cleanly in pipelines.
