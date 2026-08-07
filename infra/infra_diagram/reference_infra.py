"""AWS EKS platform architecture - Frankfurt (eu-central-1).

Drawn at explicit coordinates instead of with graphviz auto-layout, so every
box, icon and connector is positioned exactly: centring, box widths, corner
placement and the overall aspect ratio are all under direct control.

Icons are the PNGs bundled with the `diagrams` package (AWS, Kubernetes and
vendor logos) - only the layout engine changed, not the artwork.

Run:  .venv/Scripts/python.exe reference_infra.py
Out:  reference_infra.png
"""

import os

import matplotlib
matplotlib.use("Agg")

import matplotlib.pyplot as plt
from matplotlib.patches import FancyArrowPatch, FancyBboxPatch

HERE = os.path.dirname(os.path.abspath(__file__))
ICONS = os.path.join(HERE, ".venv", "Lib", "site-packages", "resources")

# --- Canvas ------------------------------------------------------------------
# 1100 x 970 drawing units, y increasing downwards. The account frame runs from
# x=120; the region starts at x=250, leaving a left-hand strip inside the
# account for services that are not VPC-bound (the S3 bucket).
W, H = 1100.0, 970.0
DPI = 200
FONT = "DejaVu Sans"
INK = "#232F3E"
ICON = 46          # icon edge length in drawing units

STYLES = {
    "account":   dict(fc="none",    ec="#C7131F", lw=2.0, ls="solid",      lc="#C7131F"),
    "region":    dict(fc="#F7F7F7", ec="#5A6C7D", lw=1.4, ls=(0, (6, 4)),  lc="#5A6C7D"),
    "vpc":       dict(fc="#FAFAFC", ec="#8C4FFF", lw=1.6, ls="solid",      lc="#8C4FFF"),
    "az":        dict(fc="#FFFFFF", ec="#5A6C7D", lw=1.1, ls=(0, (5, 4)),  lc="#5A6C7D"),
    "public":    dict(fc="#EEF5E4", ec="#7AA116", lw=1.4, ls="solid",      lc="#4F7000"),
    "private":   dict(fc="#E4F2F8", ec="#00A4A6", lw=1.4, ls="solid",      lc="#00767B"),
    "nodegroup": dict(fc="#FFFFFF", ec="#ED1C24", lw=1.6, ls="solid",      lc=INK),
    "namespace": dict(fc="#FAFBFE", ec="#4A6FA5", lw=1.1, ls=(0, (5, 4)),  lc=INK),
}

fig = plt.figure(figsize=(W / 100, H / 100), dpi=DPI)
ax = fig.add_axes([0, 0, 1, 1])
ax.set_xlim(0, W)
ax.set_ylim(H, 0)          # y grows downwards
ax.axis("off")
fig.patch.set_facecolor("white")


def box(x0, y0, x1, y1, kind, label, fontsize=9.5):
    """Container from (x0,y0) to (x1,y1), label in the top-left corner."""
    s = STYLES[kind]
    ax.add_patch(FancyBboxPatch(
        (x0, y0), x1 - x0, y1 - y0,
        boxstyle="round,pad=0,rounding_size=7",
        facecolor=s["fc"], edgecolor=s["ec"], linewidth=s["lw"], linestyle=s["ls"],
        zorder=1,
    ))
    ax.text(x0 + 10, y0 + 14, label, fontsize=fontsize, color=s["lc"],
            family=FONT, va="center", ha="left", zorder=3)


def icon(path, cx, cy, label="", size=ICON, fontsize=9.0):
    """Icon centred on (cx, cy), caption underneath."""
    img = plt.imread(os.path.join(ICONS, path))
    h, w = img.shape[0], img.shape[1]
    half_w, half_h = size / 2 * (w / max(w, h)), size / 2 * (h / max(w, h))
    ax.imshow(img, extent=(cx - half_w, cx + half_w, cy + half_h, cy - half_h),
              aspect="auto", zorder=4, interpolation="antialiased")
    for i, line in enumerate(label.split("\n")) if label else []:
        ax.text(cx, cy + size / 2 + 9 + i * 11, line, fontsize=fontsize,
                color=INK, family=FONT, ha="center", va="top", zorder=4)


def arrowhead(p0, p1, color=INK, ls="-", lw=1.3):
    ax.add_patch(FancyArrowPatch(
        p0, p1, arrowstyle="-|>", mutation_scale=12, color=color,
        linewidth=lw, linestyle=ls, shrinkA=0, shrinkB=0, zorder=6,
    ))


def route(points, color=INK, ls="-", lw=1.3):
    """Orthogonal polyline through `points`, arrowhead on the final segment."""
    for (x0, y0), (x1, y1) in zip(points, points[1:-1]):
        ax.plot([x0, x1], [y0, y1], color=color, ls=ls, lw=lw, zorder=6,
                solid_capstyle="projecting")
    arrowhead(points[-2], points[-1], color=color, ls=ls, lw=lw)


# =============================================================================
# Containers
# =============================================================================
box(120,  20, 1080, 946, "account", "AWS Account")
box(250,  44, 1050, 928, "region",  "Frankfurt (eu-central-1)")
box(266,  66, 1038, 916, "vpc",     "VPC")

# Public tier: one wide public subnet per AZ.
box(296, 176,  636, 306, "az",     "Availability Zone a")
box(312, 202,  620, 296, "public", "Public subnet")
box(666, 176, 1006, 306, "az",     "Availability Zone b")
box(682, 202,  990, 296, "public", "Public subnet")

# Private tier: EKS. The node group is centred inside the subnet, and the two
# namespace boxes are centred inside the node group.
box(286, 320, 1030, 772, "private",   "Private subnet")
box(348, 408,  968, 760, "nodegroup", "EKS CPU Node Group ( Across AZs )")
box(366, 440,  950, 566, "namespace", "System Namespaces")
box(366, 578,  950, 752, "namespace", "Applications Namespaces")

# Private tier: database.
box(286, 790, 1030, 904, "private", "Private subnet")

# =============================================================================
# Icons
# =============================================================================
# Outside the account, both on the left: the user and the git repo. The repo
# sits on ArgoCD's row so the CI/CD arrow is a straight line.
USER_Y = 88
icon("onprem/client/user.png", 62, USER_Y, "End User")
icon("onprem/vcs/github.png",  62, 490, "Code Repo")

# S3 sits in the account frame but outside the VPC - it is a regional service
# reached over the network, not something that lives in a subnet.
S3_X, S3_Y = 172, 590
icon("aws/storage/simple-storage-service-s3.png", S3_X, S3_Y, "S3\n(Loki chunks)")

# Internet Gateway in the VPC's top-left corner, clear of the End User line.
icon("aws/network/internet-gateway.png", 324, 122, "Internet Gateway")

NAT_X, ALB_X, PUB_Y = 466, 836, 234
icon("aws/network/nat-gateway.png",            NAT_X, PUB_Y, "NAT Gateway")
icon("aws/network/elastic-load-balancing.png", ALB_X, PUB_Y, "Load Balancer")

EKS_X, EKS_Y = 658, 356
icon("aws/compute/elastic-kubernetes-service.png", EKS_X, EKS_Y, "EKS")

# System namespaces: five icons centred on the box centre (x=658).
SYS = [
    ("onprem/gitops/argocd.png",      "ArgoCD"),
    ("k8s/podconfig/secret.png",      "Sealed Secrets"),
    ("onprem/monitoring/grafana.png", "Grafana"),
    ("onprem/logging/loki.png",       "Loki"),
    ("onprem/logging/fluentbit.png",  "Fluent Bit"),
]
SYS_CX, SYS_Y, SYS_STEP = 658, 490, 116
sys_x = [SYS_CX + (i - (len(SYS) - 1) / 2) * SYS_STEP for i in range(len(SYS))]
for (path, name), cx in zip(SYS, sys_x):
    icon(path, cx, SYS_Y, name)
ARGOCD_X, LOKI_X = sys_x[0], sys_x[3]

# Application namespaces: two worker nodes centred on the same axis, each with
# the EC2 instance backing it directly underneath.
APP_Y, EC2_Y = 612, 712
for cx in (EKS_X - 100, EKS_X + 100):
    icon("k8s/infra/node.png", cx, APP_Y, "EKS Worker\nNodes")
    icon("aws/compute/ec2.png", cx, EC2_Y)

# Database tier, centred in its subnet.
RDS_X, DB_Y = 658, 840
icon("aws/database/rds-postgresql-instance.png", RDS_X, DB_Y, "RDS Primary")

# =============================================================================
# Connections
# =============================================================================
# End User -> Load Balancer: over the AZ boxes, then down the gap between them.
route([(62 + ICON / 2 + 4, USER_Y), (651, USER_Y), (651, PUB_Y),
       (ALB_X - ICON / 2 - 4, PUB_Y)])

# Load Balancer -> EKS
route([(ALB_X, PUB_Y + ICON / 2 + 24), (ALB_X, 332),
       (EKS_X, 332), (EKS_X, EKS_Y - ICON / 2 - 4)])

# Code Repo -> ArgoCD
route([(62 + ICON / 2 + 4, SYS_Y), (ARGOCD_X - ICON / 2 - 4, SYS_Y)])
ax.text(140, SYS_Y - 6, "CI / CD", fontsize=9, color=INK, family=FONT,
        ha="left", va="bottom", zorder=6)

# Loki -> S3: out through the gap between the two namespace boxes, then left
# into the account strip.
route([(LOKI_X, SYS_Y + ICON / 2 + 22), (LOKI_X, 572), (240, 572),
       (240, S3_Y), (S3_X + ICON / 2 + 4, S3_Y)],
      color="#7AA116", ls=(0, (5, 3)))
ax.text(LOKI_X - 8, 567, "chunks", fontsize=8.5, color="#4F7000", family=FONT,
        ha="right", va="bottom", zorder=6)

ax.text(W / 2, 958, "AWS EKS Platform - Frankfurt (eu-central-1)",
        fontsize=15, color=INK, family=FONT, ha="center", va="center")

out = os.path.join(HERE, "reference_infra.png")
fig.savefig(out, dpi=DPI, facecolor="white")
print("wrote", out)
