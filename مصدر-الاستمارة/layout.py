#!/usr/bin/env python3
"""يولّد وسط الاستمارة (من الخانة 1 إلى التاريخ) بمسافات منتظمة، ويطبع STF_L المطابق.

    python3 layout.py            ← يكتب الأقسام في استمارة.html ويطبع مواضع الخانات
    python3 layout.py --apply    ← ويحدّث STF_L في ../index.html أيضًا

كل المقاسات بالمليمتر من أعلى يسار الصفحة.
"""
import json, re, sys, pathlib

HERE = pathlib.Path(__file__).parent
G = 4.9            # المسافة بين الأقسام
Y0 = 84.0          # أعلى عنوان الخانة 1 (تحت الخط الأخضر 77.2)
BW, BH, STEP = 8.6, 10.5, 9.8          # مربع رقم
PH_X = [26.9, 37.1, 46.9, 57.1, 66.9, 77.1, 86.9, 97.1, 106.9]
BD_X = [107.6, 117.4, 131.3, 141.1, 155.1, 164.9, 174.7, 184.5]

out, L = [], {}
r = lambda v: round(v, 2)
def add(s): out.append(s)
def num(n, left, top): add(f'<div class="num" style="left:{left}mm;top:{r(top+.4)}mm">{n}</div>')
def head(t, right, top): add(f'<div class="a h" style="right:{right}mm;top:{r(top)}mm">{t}</div>')
def box(x, y, w=BW, h=BH, cls="box", extra=""): add(f'<div class="{cls}" style="left:{r(x)}mm;top:{r(y)}mm;width:{w}mm;height:{h}mm{extra}"></div>')
def line(x, y, w): add(f'<div class="line" style="left:{r(x)}mm;width:{r(w)}mm;top:{r(y)}mm"></div>')
def text(t, top, right=None, left=None, style=""):
    pos = f"right:{right}mm" if right is not None else f"left:{left}mm"
    add(f'<div class="a" style="{pos};top:{r(top)}mm;{style}">{t}</div>')

y = Y0
# 1 name ------------------------------------------------------------
add("<!-- 1 name -->"); num(1, 186.9, y); head("اسم ولقب الطالب", 25.7, y)
bt = y + 8.2
L["t:lqb"] = [108.6, r(bt), 84.5, 11]; L["t:ism"] = [17.1, r(bt), 84.5, 11]
line(108.5, bt + 10.7, 84.6); line(17.1, bt + 10.7, 84.4)
add(f'<div class="a lab" style="right:17mm;top:{r(bt+11.7)}mm">اللقب</div>')
add(f'<div class="a lab" style="right:108.5mm;top:{r(bt+11.7)}mm">الاسم</div>')
y = bt + 11.7 + 4.8 + G

# 2 sex ---------------------------------------------------------------
add("<!-- 2 sex -->"); num(2, 186.9, y); head("الجنس", 25.7, y)
ty = y + 9.1
L["c:m"] = [185.6, r(ty), 7.5, 7.5]; L["c:f"] = [158.3, r(ty), 7.5, 7.5]
box(185.6, ty, 7.5, 7.5, "tick"); text("ذكر", ty + .4, right=27, style="font-weight:600;font-size:12.5pt")
box(158.3, ty, 7.5, 7.5, "tick"); text("أنثى", ty + .4, right=54.3, style="font-weight:600;font-size:12.5pt")
y = ty + 7.5 + G

# 3 birth date / 4 birth place -------------------------------------------------
add("<!-- 3 birth date -->"); num(3, 186.9, y); head("تاريخ الميلاد", 25.7, y)
by = y + 8.7
L["bd"] = [[x, r(by), BW, BH] for x in BD_X]
for x in BD_X: box(x, by)
for x in (127.5, 151.2): text("/", by + 4.3, left=x, style="font-size:16pt;color:var(--light)")
for lab, x, w in (("اليوم", 107.6, 18.4), ("الشهر", 131.3, 18.4), ("السنة", 155.1, 38)):
    add(f'<div class="a sub" style="left:{x}mm;width:{w}mm;top:{r(by+11.1)}mm">{lab}</div>')
add("<!-- 4 birth place -->"); num(4, 94.35, y); head("مكان الميلاد", 118.2, y)
L["t:bp"] = [17.1, r(y + 9.7), 83.5, 11]; line(17.1, y + 20.2, 83.3)
y = by + 11.1 + 4.3 + G

# 5 phones ------------------------------------------------------------
add("<!-- 5 phones -->"); num(5, 186.9, y); head("رقم الهاتف", 25.7, y)
add(f'<div class="a hint" style="right:47.6mm;top:{r(y+1.1)}mm">(هاتف الولي الذي يبقى في اتصال بالمدرسة)</div>')
for key, py, lab in (("ph", y + 8.6, "الهاتف الأول"), ("ph2", y + 22.1, 'الهاتف الثاني <span class="hint" style="font-weight:400">(إن وُجد)</span>')):
    add(f'<div class="box zero" style="left:17.1mm;top:{r(py)}mm;width:8.3mm;height:{BH}mm">0</div>')
    for x in PH_X: box(x, py)
    L[key] = [[x, r(py), BW, BH] for x in PH_X]
    text(lab, py + 1.9, right=48, style="font-weight:600;font-size:11pt")
y = y + 22.1 + BH + G

# 6 address -------------------------------------------------------------
add("<!-- 6 address -->"); num(6, 186.9, y); head("العنوان الشخصي", 25.7, y)
L["t:ad"] = [17.1, r(y + 7.2), 176, 11]; line(17.1, y + 17.7, 176)
y = y + 18.2 + G + 2

# 7 level / job ----------------------------------------------------------------
add("<!-- 7 level / job -->"); num(7, 186.9, y); head("المستوى الدراسي / المهنة", 25.7, y)
L["t:lv"] = [17.1, r(y - 4), 110, 10.5]; line(17.1, y + 6.2, 110)
y = y + 6.6 + G

# 8 current hizb / 9 balance ---------------------------------------------------
add("<!-- 8 current hizb -->"); num(8, 186.9, y); head("الحزب الذي يحفظه الآن", 25.7, y)
hy = y - 1.6
L["hz"] = [[122.7, r(hy), BW, BH], [132.5, r(hy), BW, BH]]
for x in (122.7, 132.5): box(x, hy)
add("<!-- 9 balance -->"); num(9, 94.35, y); head("الرصيد من الحفظ", 118.2, y)
L["bal"] = [[37.1, r(hy), BW, BH], [46.9, r(hy), BW, BH]]
for x in (37.1, 46.9): box(x, hy)
text("حزبًا", y + .5, right=175.2, style="font-weight:600;font-size:11pt")
y = hy + BH + G

# date ------------------------------------------------------------------------
add("<!-- date -->")
text("التاريخ", y - 1.2, right=17, style="font-weight:600;font-size:10.5pt")
line(140, y + 3.8, 38.5)
assert y + 3.8 < 258.6, f"لا يتسع: التاريخ عند {y+3.8}"

html_p = HERE / "استمارة.html"
h = html_p.read_text()
a, b = h.index("<!-- 1 name -->"), h.index("<!-- school only -->")
html_p.write_text(h[:a] + "\n".join(out) + "\n\n" + h[b:])
print(json.dumps(L, ensure_ascii=False))

if "--apply" in sys.argv:
    ip = HERE.parent / "index.html"
    t = ip.read_text()
    m = re.search(r"const STF_L=(\{.*?\});", t)
    cur = json.loads(m.group(1)); cur.update(L)
    ip.write_text(t.replace(m.group(1), json.dumps(cur, ensure_ascii=False, separators=(",", ":"))))
    print("STF_L updated")
