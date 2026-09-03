import sys, math
import numpy as np
from PIL import Image, ImageDraw, ImageFont, ImageFilter

SRC = "hands.jpg"
FONT = "/System/Library/Fonts/Menlo.ttc"

def load_mask():
    im = Image.open(SRC).convert("RGB")
    hsv = np.array(im.convert("HSV")).astype(float)
    rgb = np.array(im).astype(float)
    lum = rgb.mean(axis=2)
    sat = hsv[..., 1]
    # Hands are warm and saturated; plaster is grey. Adam's body sits bottom-left, cut it off.
    warmth = rgb[..., 0] - rgb[..., 2]
    mask = ((sat > 45) | (warmth > 28)) & (lum < 225)
    h, w = mask.shape
    yy, xx = np.mgrid[0:h, 0:w]
    mask &= ~((yy > 560) & (xx < 700))    # body / thigh region
    mask &= yy > 150
    from scipy import ndimage
    mask = ndimage.binary_opening(mask, iterations=2)
    mask = ndimage.binary_closing(mask, iterations=3)
    mask = ndimage.binary_fill_holes(mask)
    labels, n = ndimage.label(mask)
    sizes = ndimage.sum(mask, labels, range(1, n + 1))
    keep = np.argsort(sizes)[-2:] + 1
    mask = np.isin(labels, keep)
    m = Image.fromarray((mask * 255).astype(np.uint8))
    m = m.filter(ImageFilter.GaussianBlur(1.5)).point(lambda v: 255 if v > 128 else 0)
    return im, m, lum

def compose(im, m, lum, angle, size=2048, gap=(690, 395), scale=1.0):
    """Rotate about the gap so Adam's hand goes bottom-left, God's top-right; centre the gap."""
    big = int(size * 1.6)
    canvas_m = Image.new("L", (big, big), 0)
    canvas_l = Image.new("L", (big, big), 0)
    lum_im = Image.fromarray(lum.clip(0, 255).astype(np.uint8))
    s = scale * size / 1400 * 1.35
    w, h = m.size
    mr = m.resize((int(w * s), int(h * s)), Image.LANCZOS)
    lr = lum_im.resize((int(w * s), int(h * s)), Image.LANCZOS)
    gx, gy = gap[0] * s, gap[1] * s
    canvas_m.paste(mr, (int(big / 2 - gx), int(big / 2 - gy)))
    canvas_l.paste(lr, (int(big / 2 - gx), int(big / 2 - gy)))
    canvas_m = canvas_m.rotate(angle, resample=Image.BICUBIC, center=(big / 2, big / 2))
    canvas_l = canvas_l.rotate(angle, resample=Image.BICUBIC, center=(big / 2, big / 2))
    off = (big - size) // 2
    return canvas_m.crop((off, off, off + size, off + size)), canvas_l.crop((off, off, off + size, off + size))

RAMP = " .:-=+*#%@"
INNER = "+*#%@@"

def ascii_render(mask, lum, cols, size=2048, underlay=0.0, out=None):
    cell = size / cols
    rows = cols
    mk = np.array(mask).astype(float) / 255
    lm = np.array(lum).astype(float) / 255
    gy, gx = np.gradient(mk)
    font = ImageFont.truetype(FONT, int(cell * 1.02))
    img = Image.new("L", (size, size), 0)
    if underlay > 0:
        under = mask.filter(ImageFilter.GaussianBlur(cell * 0.35)).point(lambda v: int(v * underlay))
        img.paste(under)
    d = ImageDraw.Draw(img)
    # luminance range inside the hands, for the shading ramp
    inside = lm[mk > 0.5]
    lo, hi = np.percentile(inside, 8), np.percentile(inside, 92)
    for r in range(rows):
        for c in range(cols):
            y0, y1 = int(r * cell), int((r + 1) * cell)
            x0, x1 = int(c * cell), int((c + 1) * cell)
            cov = mk[y0:y1, x0:x1].mean()
            if cov < 0.12:
                continue
            if cov < 0.8:
                ax = gx[y0:y1, x0:x1].mean(); ay = gy[y0:y1, x0:x1].mean()
                ang = math.degrees(math.atan2(-ay, ax)) % 180   # gradient direction, image y down
                # edge runs perpendicular to the gradient
                if 22.5 <= ang < 67.5: ch = "\\"
                elif 67.5 <= ang < 112.5: ch = "_" if ay < 0 else "-"
                elif 112.5 <= ang < 157.5: ch = "/"
                else: ch = "|"
                fill = 255
            else:
                l = (lm[y0:y1, x0:x1].mean() - lo) / max(hi - lo, 1e-6)
                ch = INNER[int(np.clip(l, 0, 0.999) * len(INNER))]
                fill = 255
            d.text((x0 + cell / 2, y0 + cell / 2), ch, fill=fill, font=font, anchor="mm")
    if out:
        img.save(out)
    return img

if __name__ == "__main__":
    im, m, lum = load_mask()
    m.save("mask.png")
    sheet = Image.new("L", (1400, 1000), 40)
    variants = [(40, 38, 1.7), (48, 38, 1.7), (56, 38, 1.7), (40, 38, 2.0), (48, 42, 2.0), (56, 42, 2.0)]
    for i, (cols, angle, sc) in enumerate(variants):
        under = 0.0
        mask, lm = compose(im, m, lum, angle, scale=sc)
        if i == 0:
            mask.resize((512, 512)).save("compose.png")
        img = ascii_render(mask, lm, cols, underlay=under, out=f"icon_{cols}_{angle}_{int(sc*10)}.png")
        x, y = (i % 3) * 460 + 20, (i // 3) * 490 + 20
        sheet.paste(img.resize((360, 360), Image.LANCZOS), (x, y))
        sheet.paste(img.resize((180, 180), Image.LANCZOS), (x + 370, y))
        sheet.paste(img.resize((60, 60), Image.LANCZOS), (x + 370, y + 190))
        ImageDraw.Draw(sheet).text((x, y + 370), f"cols={cols} angle={angle} scale={sc}", fill=255, font=ImageFont.truetype(FONT, 22))
    sheet.save("sheet.png")
    print("ok")

def separate(mask, lum, angle, push):
    """Push the two hands apart along the diagonal so the gap is unmistakable."""
    from scipy import ndimage
    mk = np.array(mask) > 128
    lm = np.array(lum)
    labels, n = ndimage.label(mk)
    out_m = np.zeros_like(mk); out_l = np.zeros_like(lm)
    h, w = mk.shape
    for i in range(1, n + 1):
        comp = labels == i
        cy, cx = ndimage.center_of_mass(comp)
        # bottom-left component moves down-left, top-right moves up-right
        sign = 1 if (cx - w / 2) - (h / 2 - cy) > 0 else -1
        dx = int(sign * push * math.cos(math.radians(angle)))
        dy = int(-sign * push * math.sin(math.radians(angle)))
        shifted = ndimage.shift(comp.astype(np.uint8), (dy, dx), order=0, mode="constant", cval=0) > 0
        lshift = ndimage.shift(lm, (dy, dx), order=1, mode="constant", cval=0)
        out_m |= shifted
        out_l = np.where(shifted, lshift, out_l)
    return Image.fromarray((out_m * 255).astype(np.uint8)), Image.fromarray(out_l.astype(np.uint8))

def final(cols=44, angle=40, scale=1.9, push=0.035, size=2048, name="final"):
    im, m, lum = load_mask()
    mask, lm = compose(im, m, lum, angle, size=size, scale=scale)
    mask, lm = separate(mask, lm, angle, int(size * push))
    mask.resize((512, 512)).save(f"{name}_mask.png")
    img = ascii_render(mask, lm, cols, size=size)
    img.resize((1024, 1024), Image.LANCZOS).save(f"{name}_1024.png")
    sheet = Image.new("L", (1024 + 20 + 180 + 20, 1024), 40)
    sheet.paste(img.resize((1024, 1024), Image.LANCZOS), (0, 0))
    sheet.paste(img.resize((180, 180), Image.LANCZOS), (1044, 0))
    sheet.paste(img.resize((120, 120), Image.LANCZOS), (1044, 200))
    sheet.paste(img.resize((60, 60), Image.LANCZOS), (1044, 340))
    sheet.save(f"{name}_sheet.png")
