"""UI 设计系统生成器 —— 唯一的调色板来源。

设计语言「软胶囊」:
  大圆角胶囊按钮/列表行, 无描边, 用色块深浅分层; 主操作为深色(浅色主题)/奶油色(深色主题)胶囊;
  选中态为饱和色块填充; 分隔线为圆点虚线; 粗字重 + 高对比文字, 数据页清晰易读。

生成:
  assets/ui/theme_light.tres  浅色「奶油纸」: 奶油底 + 暖炭文字 + 青绿选中 + 珊瑚点缀
  assets/ui/theme_dark.tres   深色「夜炉」:   暖黑底 + 奶油文字 + 青绿选中, 主按钮反转为奶油胶囊
  scripts/ui/ui_palette.gd    同一调色板的 GDScript 常量, 供 UITheme.color() 使用

用法: python tools/gen_ui_theme.py
"""
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent

PALETTES = {
    "light": {
        "bg": "#f1ebe1", "surface": "#fbf8f2", "surface2": "#ede6da", "surface3": "#e1d8c9",
        "border": "#cfc4b2", "text": "#3a332c", "muted": "#857a6d", "faint": "#bbb09f",
        "accent": "#279c91", "accent_text": "#ffffff", "accent2": "#ef7655",
        "cta": "#3a332c", "cta_text": "#fbf8f2",
        "danger": "#e0534a", "success": "#3f9e5c", "warning": "#e39a1f",
        "cyan": "#3fa9cf", "amber": "#eaa52e", "pink": "#e8708f", "violet": "#8a76db",
        "ink": "#3a332c", "shadow": "#5a462e22",
    },
    "dark": {
        "bg": "#1b191e", "surface": "#25222a", "surface2": "#2f2b35", "surface3": "#3a3541",
        "border": "#4a4452", "text": "#f3ede4", "muted": "#aaa093", "faint": "#6a6271",
        "accent": "#4cc4b4", "accent_text": "#10221f", "accent2": "#ff8f6b",
        "cta": "#f3ede4", "cta_text": "#25222a",
        "danger": "#ff6b61", "success": "#5fcf83", "warning": "#ffb84d",
        "cyan": "#5cc3e6", "amber": "#ffc053", "pink": "#ff8fab", "violet": "#a594ff",
        "ink": "#121015", "shadow": "#00000066",
    },
}

PILL = 99
PANEL_R = 28
CARD_R = 24


def col(hexstr, alpha=None):
    h = hexstr.lstrip("#")
    r, g, b = (int(h[i:i + 2], 16) / 255 for i in (0, 2, 4))
    a = int(h[6:8], 16) / 255 if len(h) == 8 else 1.0
    if alpha is not None:
        a = alpha
    return f"Color({r:.4g}, {g:.4g}, {b:.4g}, {a:.4g})"


def mix(a, b, t):
    ha, hb = a.lstrip("#")[:6], b.lstrip("#")[:6]
    ca = [int(ha[i:i + 2], 16) for i in (0, 2, 4)]
    cb = [int(hb[i:i + 2], 16) for i in (0, 2, 4)]
    return "#" + "".join(f"{round(x + (y - x) * t):02x}" for x, y in zip(ca, cb))


class Builder:
    def __init__(self):
        self.subs = []
        self.props = []
        self.n = 0

    def box(self, bg, radius=PILL, pad=(18, 10), border=None, bw=0, shadow=None, shadow_size=0,
            shadow_offset=(0, 0), draw_center=True, expand=None):
        """pad = (x, y) 或 (left, top, right, bottom)"""
        self.n += 1
        sid = f"StyleBoxFlat_{self.n}"
        if len(pad) == 2:
            pad = (pad[0], pad[1], pad[0], pad[1])
        lines = [f'[sub_resource type="StyleBoxFlat" id="{sid}"]',
                 f"content_margin_left = {pad[0]}.0", f"content_margin_top = {pad[1]}.0",
                 f"content_margin_right = {pad[2]}.0", f"content_margin_bottom = {pad[3]}.0",
                 f"bg_color = {bg}"]
        if not draw_center:
            lines.append("draw_center = false")
        if border and bw:
            lines += [f"border_width_left = {bw}", f"border_width_top = {bw}",
                      f"border_width_right = {bw}", f"border_width_bottom = {bw}",
                      f"border_color = {border}"]
        if radius:
            lines += [f"corner_radius_top_left = {radius}", f"corner_radius_top_right = {radius}",
                      f"corner_radius_bottom_right = {radius}", f"corner_radius_bottom_left = {radius}",
                      "corner_detail = 10"]
        if expand:
            for side, v in zip(("left", "top", "right", "bottom"), expand):
                if v:
                    lines.append(f"expand_margin_{side} = {v}.0")
        if shadow and shadow_size:
            lines += [f"shadow_color = {shadow}", f"shadow_size = {shadow_size}",
                      f"shadow_offset = Vector2({shadow_offset[0]}, {shadow_offset[1]})"]
        lines.append("anti_aliasing_size = 0.75")
        self.subs.append("\n".join(lines))
        return f'SubResource("{sid}")'

    def tex(self, ext_id, modulate, vertical=True):
        """滚动条: 纹理左侧(或上侧) 10px 透明, 只在外侧绘制 6px 胶囊"""
        self.n += 1
        sid = f"StyleBoxTexture_{self.n}"
        if vertical:
            m = ("texture_margin_top = 4.0\ntexture_margin_bottom = 4.0\n"
                 "content_margin_left = 16.0\ncontent_margin_top = 4.0\ncontent_margin_bottom = 4.0")
        else:
            m = ("texture_margin_left = 4.0\ntexture_margin_right = 4.0\n"
                 "content_margin_top = 16.0\ncontent_margin_left = 4.0\ncontent_margin_right = 4.0")
        self.subs.append(f'[sub_resource type="StyleBoxTexture" id="{sid}"]\n'
                         f'texture = ExtResource("{ext_id}")\n{m}\nmodulate_color = {modulate}')
        return f'SubResource("{sid}")'

    def dots(self, ext_id, modulate, vertical=False):
        """圆点虚线: 平铺小圆点纹理"""
        self.n += 1
        sid = f"StyleBoxTexture_{self.n}"
        axis = "axis_stretch_vertical = 1" if vertical else "axis_stretch_horizontal = 1"
        self.subs.append(f'[sub_resource type="StyleBoxTexture" id="{sid}"]\n'
                         f'texture = ExtResource("{ext_id}")\n{axis}\nmodulate_color = {modulate}')
        return f'SubResource("{sid}")'

    def empty(self, pad=None):
        self.n += 1
        sid = f"StyleBoxEmpty_{self.n}"
        s = f'[sub_resource type="StyleBoxEmpty" id="{sid}"]'
        if pad:
            if len(pad) == 2:
                pad = (pad[0], pad[1], pad[0], pad[1])
            s += (f"\ncontent_margin_left = {pad[0]}.0\ncontent_margin_top = {pad[1]}.0"
                  f"\ncontent_margin_right = {pad[2]}.0\ncontent_margin_bottom = {pad[3]}.0")
        self.subs.append(s)
        return f'SubResource("{sid}")'

    def set(self, key, value):
        self.props.append(f"{key} = {value}")


def button_family(b, p, name, normal, hover, pressed, disabled, focus, fg, fg_hover, fg_pressed):
    b.set(f"{name}/styles/normal", normal)
    b.set(f"{name}/styles/hover", hover)
    b.set(f"{name}/styles/pressed", pressed)
    b.set(f"{name}/styles/hover_pressed", pressed)
    b.set(f"{name}/styles/disabled", disabled)
    b.set(f"{name}/styles/focus", focus)
    for st, c in (("font_color", fg), ("font_hover_color", fg_hover), ("font_pressed_color", fg_pressed),
                  ("font_hover_pressed_color", fg_pressed), ("font_focus_color", fg),
                  ("icon_normal_color", fg), ("icon_hover_color", fg_hover), ("icon_pressed_color", fg_pressed),
                  ("icon_hover_pressed_color", fg_pressed), ("icon_focus_color", fg)):
        b.set(f"{name}/colors/{st}", c)
    b.set(f"{name}/colors/font_disabled_color", col(p["faint"]))
    b.set(f"{name}/colors/icon_disabled_color", col(p["faint"]))


def build(mode):
    p = PALETTES[mode]
    dark = mode == "dark"
    b = Builder()
    text, muted = col(p["text"]), col(p["muted"])
    focus = b.box(col("#000000", 0), PILL, (0, 0), col(p["accent"]), 3, draw_center=False, expand=(3, 3, 3, 3))
    focus_card = b.box(col("#000000", 0), CARD_R + 3, (0, 0), col(p["accent"]), 3, draw_center=False, expand=(3, 3, 3, 3))
    disabled = b.box(col(p["surface2"], 0.5), PILL, (20, 11))
    soft_shadow = dict(shadow=col(p["shadow"]), shadow_size=22 if not dark else 26, shadow_offset=(0, 8))
    small_shadow = dict(shadow=col(p["shadow"]), shadow_size=12, shadow_offset=(0, 4))

    # ===== 按钮：色块胶囊，无描边 =====
    btn_n = b.box(col(p["surface2"]), PILL, (20, 11))
    btn_h = b.box(col(p["surface3"]), PILL, (20, 11))
    btn_p = b.box(col(p["accent"]), PILL, (20, 11))
    for name in ("Button", "OptionButton", "MenuButton"):
        button_family(b, p, name, btn_n, btn_h, btn_p, disabled, focus, text, text, col(p["accent_text"]))
    b.set("Button/constants/h_separation", 10)
    b.set("OptionButton/constants/arrow_margin", 14)

    # 主操作：深色 / 奶油色胶囊
    b.set("AccentButton/base_type", '&"Button"')
    cta_h = mix(p["cta"], p["accent"], 0.18)
    button_family(b, p, "AccentButton",
                  b.box(col(p["cta"]), PILL, (26, 12), **small_shadow),
                  b.box(col(cta_h), PILL, (26, 12), shadow=col(p["shadow"]), shadow_size=18, shadow_offset=(0, 6)),
                  b.box(col(mix(p["cta"], p["bg"], 0.15)), PILL, (26, 12)),
                  disabled, focus, col(p["cta_text"]), col(p["cta_text"]), col(p["cta_text"]))

    # 幽灵按钮
    b.set("GhostButton/base_type", '&"Button"')
    button_family(b, p, "GhostButton",
                  b.box(col(p["surface2"], 0), PILL, (14, 9)),
                  b.box(col(p["surface2"]), PILL, (14, 9)),
                  b.box(col(p["surface3"]), PILL, (14, 9)),
                  b.empty((14, 9)), focus, muted, text, text)

    # 危险按钮
    b.set("DangerButton/base_type", '&"Button"')
    button_family(b, p, "DangerButton",
                  b.box(col(mix(p["surface"], p["danger"], 0.14)), PILL, (20, 11)),
                  b.box(col(mix(p["surface"], p["danger"], 0.24)), PILL, (20, 11)),
                  b.box(col(p["danger"]), PILL, (20, 11)),
                  disabled, focus, col(p["danger"]), col(p["danger"]), "Color(1, 1, 1, 1)")

    # 侧栏导航：选中为饱和色块
    b.set("NavButton/base_type", '&"Button"')
    button_family(b, p, "NavButton",
                  b.box(col(p["surface2"], 0), PILL, (18, 10)),
                  b.box(col(p["surface2"]), PILL, (18, 10)),
                  b.box(col(p["accent"]), PILL, (18, 10)),
                  b.empty((18, 10)), focus, muted, text, col(p["accent_text"]))

    for name in ("CheckBox", "CheckButton"):
        b.set(f"{name}/styles/normal", b.empty((6, 4)))
        b.set(f"{name}/styles/hover", b.box(col(p["surface2"]), PILL, (6, 4)))
        b.set(f"{name}/styles/pressed", b.empty((6, 4)))
        b.set(f"{name}/styles/hover_pressed", b.box(col(p["surface2"]), PILL, (6, 4)))
        b.set(f"{name}/styles/focus", focus)
        for st in ("font_color", "font_hover_color", "font_pressed_color", "font_hover_pressed_color", "font_focus_color"):
            b.set(f"{name}/colors/{st}", text)

    # ===== 面板 =====
    panel = b.box(col(p["surface"]), PANEL_R, (24, 22), **soft_shadow)
    b.set("Panel/styles/panel", panel)
    b.set("PanelContainer/styles/panel", panel)
    b.set("CardPanel/base_type", '&"PanelContainer"')
    b.set("CardPanel/styles/panel", b.box(col(p["surface"]), PANEL_R, (24, 22), **soft_shadow))
    b.set("CardPanelActive/base_type", '&"PanelContainer"')
    b.set("CardPanelActive/styles/panel", b.box(col(p["surface"]), PANEL_R, (24, 22), col(p["accent"]), 3, **soft_shadow))
    b.set("BarPanel/base_type", '&"PanelContainer"')
    b.set("BarPanel/styles/panel", b.box(col(p["surface"], 0.9), 0, (28, 12)))
    b.set("ChipPanel/base_type", '&"PanelContainer"')
    b.set("ChipPanel/styles/panel", b.box(col(p["surface2"]), PILL, (14, 5)))
    b.set("InsetPanel/base_type", '&"PanelContainer"')
    b.set("InsetPanel/styles/panel", b.box(col(p["surface2"]), 22, (16, 12)))
    b.set("GlassPanel/base_type", '&"PanelContainer"')
    b.set("GlassPanel/styles/panel", b.box(col(p["surface"], 0.94), PANEL_R, (20, 18), **soft_shadow))
    # 数据行：胶囊色块
    b.set("RowPanel/base_type", '&"PanelContainer"')
    b.set("RowPanel/styles/panel", b.box(col(p["surface2"]), PILL, (8, 6, 20, 6)))

    # ===== 文本 =====
    b.set("Label/colors/font_color", text)
    b.set("Label/colors/font_shadow_color", col("#000000", 0))
    b.set("RichTextLabel/colors/default_color", text)
    b.set("TitleLabel/base_type", '&"Label"')
    b.set("TitleLabel/fonts/font", 'SubResource("FontVariation_display")')
    b.set("TitleLabel/font_sizes/font_size", 36)
    b.set("TitleLabel/colors/font_color", text)
    b.set("HeaderLabel/base_type", '&"Label"')
    b.set("HeaderLabel/fonts/font", 'SubResource("FontVariation_heavy")')
    b.set("HeaderLabel/font_sizes/font_size", 21)
    b.set("HeaderLabel/colors/font_color", text)
    b.set("MutedLabel/base_type", '&"Label"')
    b.set("MutedLabel/font_sizes/font_size", 15)
    b.set("MutedLabel/colors/font_color", muted)
    b.set("AccentLabel/base_type", '&"Label"')
    b.set("AccentLabel/fonts/font", 'SubResource("FontVariation_heavy")')
    b.set("AccentLabel/colors/font_color", col(p["accent"]))
    b.set("EyebrowLabel/base_type", '&"Label"')
    b.set("EyebrowLabel/fonts/font", 'SubResource("FontVariation_heavy")')
    b.set("EyebrowLabel/font_sizes/font_size", 15)
    b.set("EyebrowLabel/colors/font_color", text)
    b.set("ValueLabel/base_type", '&"Label"')
    b.set("ValueLabel/fonts/font", 'SubResource("FontVariation_display")')
    b.set("ValueLabel/font_sizes/font_size", 20)
    b.set("ValueLabel/colors/font_color", text)

    # 局内 HUD 数据块（两行文本：名称 / 数值）
    b.set("StatTileLabel/base_type", '&"Label"')
    b.set("StatTileLabel/styles/normal", b.box(col(p["surface"], 0.96), CARD_R, (18, 10), **small_shadow))
    b.set("StatTileLabel/fonts/font", 'SubResource("FontVariation_heavy")')
    b.set("StatTileLabel/font_sizes/font_size", 22)
    b.set("StatTileLabel/colors/font_color", text)
    b.set("StatTileLabel/constants/line_spacing", 2)

    # ===== 输入 =====
    le_n = b.box(col(p["surface2"]), PILL, (22, 12))
    le_f = b.box(col(p["surface2"]), PILL, (22, 12), col(p["accent"]), 3)
    for name in ("LineEdit", "TextEdit", "SpinBox"):
        b.set(f"{name}/styles/normal", le_n)
        b.set(f"{name}/styles/focus", le_f)
        b.set(f"{name}/styles/read_only", b.box(col(p["surface2"], 0.5), PILL, (22, 12)))
        b.set(f"{name}/colors/font_color", text)
        b.set(f"{name}/colors/font_placeholder_color", col(p["faint"]))
        b.set(f"{name}/colors/caret_color", col(p["accent"]))
        b.set(f"{name}/colors/selection_color", col(p["accent"], 0.3))
    b.set("TextEdit/styles/normal", b.box(col(p["surface2"]), 22, (16, 12)))
    b.set("LineEdit/constants/caret_width", 2)

    # ===== 弹出层 / 提示 =====
    b.set("PopupMenu/styles/panel", b.box(col(p["surface"]), 22, (8, 8), **soft_shadow))
    b.set("PopupMenu/styles/hover", b.box(col(p["accent"]), PILL, (12, 7)))
    b.set("PopupMenu/styles/separator", b.dots("4_doth", col(p["border"])))
    b.set("PopupMenu/colors/font_color", text)
    b.set("PopupMenu/colors/font_hover_color", col(p["accent_text"]))
    b.set("PopupMenu/colors/font_disabled_color", col(p["faint"]))
    b.set("PopupMenu/constants/v_separation", 12)
    b.set("PopupMenu/constants/item_start_padding", 12)
    b.set("TooltipPanel/styles/panel", b.box(col(p["cta"]), 14, (14, 8)))
    b.set("TooltipLabel/colors/font_color", col(p["cta_text"]))
    b.set("TooltipLabel/font_sizes/font_size", 14)
    for name in ("AcceptDialog", "ConfirmationDialog", "Window"):
        b.set(f"{name}/styles/panel", b.box(col(p["surface"]), PANEL_R, (22, 20)))
        b.set(f"{name}/styles/embedded_border", b.box(col(p["surface"]), PANEL_R, (22, 34), **soft_shadow))
    b.set("Window/colors/title_color", text)

    # ===== 滑块 / 滚动条 / 进度条 =====
    track = b.box(col(p["surface3"]), PILL, (0, 4))
    fill = b.box(col(p["accent"]), PILL, (0, 4))
    for name in ("HSlider", "VSlider"):
        b.set(f"{name}/styles/slider", track)
        b.set(f"{name}/styles/grabber_area", fill)
        b.set(f"{name}/styles/grabber_area_highlight", fill)
    track_c = col(p["surface3"], 0.7)
    grab_c = col(p["faint"])
    grab_h = col(p["accent"])
    for name, ext, vert in (("VScrollBar", "2_sbv", True), ("HScrollBar", "3_sbh", False)):
        tr_ = b.tex(ext, track_c, vert)
        b.set(f"{name}/styles/scroll", tr_)
        b.set(f"{name}/styles/scroll_focus", tr_)
        b.set(f"{name}/styles/grabber", b.tex(ext, grab_c, vert))
        hl = b.tex(ext, grab_h, vert)
        b.set(f"{name}/styles/grabber_highlight", hl)
        b.set(f"{name}/styles/grabber_pressed", hl)
    b.set("ProgressBar/styles/background", b.box(col(p["surface3"]), PILL, (0, 4)))
    b.set("ProgressBar/styles/fill", b.box(col(p["accent"]), PILL, (0, 4)))
    b.set("ProgressBar/colors/font_color", text)

    # ===== 分隔线：圆点虚线 =====
    b.set("HSeparator/styles/separator", b.dots("4_doth", col(p["border"])))
    b.set("HSeparator/constants/separation", 16)
    b.set("VSeparator/styles/separator", b.dots("5_dotv", col(p["border"]), True))
    b.set("VSeparator/constants/separation", 16)

    # ===== 标签页：胶囊分段 =====
    b.set("TabContainer/styles/panel", panel)
    b.set("TabContainer/styles/tabbar_background", b.box(col(p["surface2"]), PILL, (4, 4)))
    for name in ("TabContainer", "TabBar"):
        b.set(f"{name}/styles/tab_selected", b.box(col(p["accent"]), PILL, (18, 8)))
        b.set(f"{name}/styles/tab_hovered", b.box(col(p["surface3"]), PILL, (18, 8)))
        b.set(f"{name}/styles/tab_unselected", b.box(col(p["surface2"], 0), PILL, (18, 8)))
        b.set(f"{name}/styles/tab_focus", focus)
        b.set(f"{name}/colors/font_selected_color", col(p["accent_text"]))
        b.set(f"{name}/colors/font_hovered_color", text)
        b.set(f"{name}/colors/font_unselected_color", muted)

    # ===== 列表 =====
    for name in ("ItemList", "Tree"):
        b.set(f"{name}/styles/panel", b.box(col(p["surface2"]), 22, (8, 8)))
        b.set(f"{name}/styles/selected", b.box(col(p["accent"], 0.85), PILL, (10, 6)))
        b.set(f"{name}/styles/selected_focus", b.box(col(p["accent"]), PILL, (10, 6)))
        b.set(f"{name}/styles/hovered", b.box(col(p["surface3"]), PILL, (10, 6)))
        b.set(f"{name}/colors/font_color", text)
        b.set(f"{name}/colors/font_selected_color", col(p["accent_text"]))

    b.set("ScrollContainer/styles/panel", b.empty())
    _ = focus_card

    header = ('[gd_resource type="Theme" format=3]\n\n'
              '[ext_resource type="FontFile" uid="uid://bdubfn3esh6n1" path="res://assets/fonts/NotoSansSC-wght.ttf" id="1_font"]\n'
              '[ext_resource type="Texture2D" path="res://assets/ui/scroll_v.png" id="2_sbv"]\n'
              '[ext_resource type="Texture2D" path="res://assets/ui/scroll_h.png" id="3_sbh"]\n'
              '[ext_resource type="Texture2D" path="res://assets/ui/dot_h.png" id="4_doth"]\n'
              '[ext_resource type="Texture2D" path="res://assets/ui/dot_v.png" id="5_dotv"]\n\n'
              '[sub_resource type="FontVariation" id="FontVariation_ui"]\nbase_font = ExtResource("1_font")\n'
              "variation_opentype = {\n2003265652: 640.0\n}\n\n"
              '[sub_resource type="FontVariation" id="FontVariation_heavy"]\nbase_font = ExtResource("1_font")\n'
              "variation_opentype = {\n2003265652: 800.0\n}\n\n"
              '[sub_resource type="FontVariation" id="FontVariation_display"]\nbase_font = ExtResource("1_font")\n'
              "variation_opentype = {\n2003265652: 900.0\n}\n")
    body = "\n\n".join(b.subs)
    res = ('[resource]\ndefault_font = SubResource("FontVariation_ui")\ndefault_font_size = 16\n'
           + "\n".join(b.props) + "\n")
    return header + "\n" + body + "\n\n" + res


def gd_palette():
    out = ["extends RefCounted", "", "## 由 tools/gen_ui_theme.py 生成，请勿手改", "", "const PALETTES := {"]
    for m, p in PALETTES.items():
        out.append(f'\t"{m}": {{')
        for k, v in p.items():
            out.append(f'\t\t"{k}": Color("{v}"),')
        out.append("\t},")
    out.append("}")
    return "\n".join(out) + "\n"


if __name__ == "__main__":
    for m in PALETTES:
        out = ROOT / "assets" / "ui" / f"theme_{m}.tres"
        out.write_text(build(m), encoding="utf-8", newline="\n")
        print("wrote", out)
    pal = ROOT / "scripts" / "ui" / "ui_palette.gd"
    pal.write_text(gd_palette(), encoding="utf-8", newline="\n")
    print("wrote", pal)
