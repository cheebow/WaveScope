#!/usr/bin/env python3
"""WaveScope アイコンの SVG レイヤー生成"""
import os

OUT = "/Users/cheebow/Dev/WaveScope/Design/AppIcon"
S = 1024
CY = S / 2

# 波形バー: min/max ビン描画(アプリの実描画と同じ見た目)を意識した左右対称バー
fracs = [0.34, 0.62, 0.46, 0.88, 0.58, 1.00, 0.74, 0.42, 0.66, 0.94, 0.70, 0.52, 0.80, 0.44, 0.30]
BAR_W = 30
GAP = 20
MAX_H = 270  # 中心からの最大振幅(px)
total_w = len(fracs) * BAR_W + (len(fracs) - 1) * GAP
x0 = (S - total_w) / 2

def bars_svg(color="#FFFFFF"):
    rects = []
    for i, f in enumerate(fracs):
        h = 2 * MAX_H * f
        x = x0 + i * (BAR_W + GAP)
        y = CY - MAX_H * f
        rects.append(f'  <rect x="{x:.1f}" y="{y:.1f}" width="{BAR_W}" height="{h:.1f}" rx="{BAR_W/2}" fill="{color}"/>')
    return "\n".join(rects)

waveform = f'''<svg xmlns="http://www.w3.org/2000/svg" width="{S}" height="{S}" viewBox="0 0 {S} {S}">
{bars_svg()}
</svg>
'''

# 再生ヘッド: バー9本目と10本目の間(ギャップ中央)に配置
ph_x = x0 + 9 * (BAR_W + GAP) - GAP / 2
playhead = f'''<svg xmlns="http://www.w3.org/2000/svg" width="{S}" height="{S}" viewBox="0 0 {S} {S}">
  <rect x="{ph_x - 8:.1f}" y="182" width="16" height="660" rx="8" fill="#FFFFFF"/>
</svg>
'''

# 背景(Icon Composer 側のグラデ指定を使う場合は不要だが、参考用に同梱)
background = f'''<svg xmlns="http://www.w3.org/2000/svg" width="{S}" height="{S}" viewBox="0 0 {S} {S}">
  <defs>
    <linearGradient id="bg" x1="0" y1="0" x2="0" y2="1">
      <stop offset="0" stop-color="#4A90F7"/>
      <stop offset="1" stop-color="#0B2E70"/>
    </linearGradient>
  </defs>
  <rect width="{S}" height="{S}" fill="url(#bg)"/>
</svg>
'''

# プレビュー(合成 + squircle 近似マスク)
preview = f'''<svg xmlns="http://www.w3.org/2000/svg" width="{S}" height="{S}" viewBox="0 0 {S} {S}">
  <defs>
    <linearGradient id="bg" x1="0" y1="0" x2="0" y2="1">
      <stop offset="0" stop-color="#4A90F7"/>
      <stop offset="1" stop-color="#0B2E70"/>
    </linearGradient>
    <clipPath id="squircle"><rect width="{S}" height="{S}" rx="230"/></clipPath>
  </defs>
  <g clip-path="url(#squircle)">
    <rect width="{S}" height="{S}" fill="url(#bg)"/>
    <rect x="{ph_x - 8:.1f}" y="182" width="16" height="660" rx="8" fill="#FFFFFF" opacity="0.85"/>
{bars_svg()}
  </g>
</svg>
'''

os.makedirs(OUT, exist_ok=True)
for name, content in [("waveform.svg", waveform), ("playhead.svg", playhead),
                      ("background.svg", background), ("preview.svg", preview)]:
    with open(os.path.join(OUT, name), "w") as f:
        f.write(content)
print("playhead x =", ph_x)
print("bars from", x0, "to", x0 + total_w)
