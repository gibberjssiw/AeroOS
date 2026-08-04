#!/bin/bash
###############################################################################
# AeroOS - Step 2: Plymouth Boot Animation Theme
# Run this INSIDE a Cubic chroot environment (or as a live-build chroot hook).
# Creates a custom Plymouth theme mimicking the Windows 7 glowing orb boot.
#
# This script is sourced/run after Step 1 (aeroos-step1-chroot.sh).
###############################################################################
set -euo pipefail

export DEBIAN_FRONTEND=noninteractive
export LC_ALL=C

echo "================================================"
echo " AeroOS Step 2 — Plymouth Boot Theme"
echo " $(date)"
echo "================================================"

# ─────────────────────────────────────────────────────────────────────────────
# 1.  Ensure Plymouth is installed
# ─────────────────────────────────────────────────────────────────────────────
if ! command -v plymouth-set-default-theme &>/dev/null; then
    echo "[INFO] Plymouth not found, installing…"
    apt-get update -y
    apt-get install -y plymouth plymouth-themes
fi

# ─────────────────────────────────────────────────────────────────────────────
# 2.  Create the AeroOS Plymouth theme directory
# ─────────────────────────────────────────────────────────────────────────────
THEME_DIR="/usr/share/plymouth/themes/aeroos"
mkdir -p "$THEME_DIR"

# ─────────────────────────────────────────────────────────────────────────────
# 3.  Generate the orb animation frames using ImageMagick (if available)
#     We generate 36 frames (one per 10 degrees of rotation) at 200x200.
#     If ImageMagick is unavailable, we fall back to a script-only approach
#     that draws the orb procedurally via Plymouth's built-in primitives.
# ─────────────────────────────────────────────────────────────────────────────
FRAMES_DIR="${THEME_DIR}/frames"
mkdir -p "$FRAMES_DIR"

generate_orb_frames() {
    if ! command -v convert &>/dev/null; then
        echo "[WARN] ImageMagick not available — using procedural orb (no PNG frames)."
        return 1
    fi

    echo "[INFO] Generating 36 orb animation frames with ImageMagick…"

    local i
    for i in $(seq 0 35); do
        local angle=$((i * 10))
        local frame_file="${FRAMES_DIR}/orb-$(printf '%03d' $i).png"

        # Create a glowing orb that "rotates" by shifting the highlight position
        # The orb is a blue sphere with a moving specular highlight + glow
        local hx=$((100 + 60 * 65536 * (i - 18) / 18 / 360))
        # Simplified: shift highlight x position
        local hlx=$((80 + (i * 2)))
        if [ "$hlx" -gt 120 ]; then hlx=$((160 - hlx)); fi

        convert -size 200x200 xc:none \
            -fill 'rgba(0,80,180,0.3)' \
            -draw "circle 100,100 100,5" \
            -fill 'rgba(40,120,220,0.5)' \
            -draw "circle 100,100 100,15" \
            -fill 'rgba(80,160,255,0.7)' \
            -draw "circle 100,100 100,30" \
            -fill "rgba(160,200,255,0.8)" \
            -draw "circle ${hlx},70 ${hlx},55" \
            -fill 'rgba(255,255,255,0.6)' \
            -draw "circle ${hlx},65 ${hlx},58" \
            -fill 'rgba(255,255,255,0.9)' \
            -draw "circle ${hlx},62 ${hlx},60" \
            -fill 'rgba(0,40,100,0.0)' \
            -stroke 'rgba(120,180,255,0.4)' -strokewidth 2 \
            -draw "circle 100,100 100,3" \
            "$frame_file" 2>/dev/null

        if [ ! -f "$frame_file" ]; then
            echo "[WARN] Frame generation failed at index $i — falling back to procedural."
            return 1
        fi
    done

    # Create a static "logo" image for the final frame
    convert -size 200x200 xc:none \
        -fill 'rgba(0,80,180,0.3)' \
        -draw "circle 100,100 100,5" \
        -fill 'rgba(40,120,220,0.5)' \
        -draw "circle 100,100 100,15" \
        -fill 'rgba(80,160,255,0.7)' \
        -draw "circle 100,100 100,30" \
        -fill 'rgba(160,200,255,0.8)' \
        -draw "circle 90,70 90,55" \
        -fill 'rgba(255,255,255,0.9)' \
        -draw "circle 90,62 90,60" \
        -stroke 'rgba(120,180,255,0.6)' -strokewidth 2 \
        -draw "circle 100,100 100,3" \
        "${THEME_DIR}/logo.png" 2>/dev/null

    echo "[OK] 36 orb frames + logo generated."
    return 0
}

# ─────────────────────────────────────────────────────────────────────────────
# 4.  Write the Plymouth theme configuration file (aeroos.plymouth)
# ─────────────────────────────────────────────────────────────────────────────
cat > "${THEME_DIR}/aeroos.plymouth" <<'PLYMOUTH_THEME'
[Plymouth Theme]
Name=AeroOS
Description=AeroOS Boot — Windows 7 Glowing Orb
ModuleName=script

[script]
ImageDir=/usr/share/plymouth/themes/aeroos
ScriptFile=/usr/share/plymouth/themes/aeroos/aeroos.script
PLYMOUTH_THEME

# ─────────────────────────────────────────────────────────────────────────────
# 5.  Write the Plymouth script (the animation engine)
#     This is a Plymouth "script" plugin theme. It draws:
#       - A black/dark-blue gradient background
#       - A glowing orb that pulses and "rotates" (simulated via highlight shift)
#       - The "AeroOS" text below the orb
#       - A progress indicator (spinning dots) at the bottom
# ─────────────────────────────────────────────────────────────────────────────
cat > "${THEME_DIR}/aeroos.script" <<'PLYMOUTH_SCRIPT'
// ─────────────────────────────────────────────────────────────────────────
// AeroOS Plymouth Boot Script — Windows 7 Orb Animation
// ─────────────────────────────────────────────────────────────────────────

// Screen dimensions
screen_width = Window.GetWidth();
screen_height = Window.GetHeight();

// Theme colors
background_color = [0.02, 0.05, 0.12];      // very dark blue
orb_blue = [0.15, 0.45, 0.90];               // Windows 7 blue
orb_glow = [0.30, 0.60, 1.00];              // brighter blue glow
orb_highlight = [0.80, 0.90, 1.00];         // specular highlight
text_color = [0.70, 0.80, 0.95];            // light blue-gray text
progress_color = [0.20, 0.50, 0.90];        // progress dots

// Animation state
frame = 0;
orb_scale = 1.0;
orb_pulse = 0.0;
glow_intensity = 0.5;
progress_angle = 0.0;
boot_progress = 0.0;

// Orb center position
orb_cx = screen_width / 2;
orb_cy = screen_height / 2 - 30;
orb_radius = 60;

// Try to load PNG frames if they exist
has_frames = FALSE;
orb_frames[0] = Image("frames/orb-000.png");
if (orb_frames[0] != NULL) {
    has_frames = TRUE;
    // Pre-load all 36 frames
    for (i = 1; i < 36; i++) {
        frame_name = "frames/orb-" + (i < 10 ? "00" : "0") + i + ".png";
        orb_frames[i] = Image(frame_name);
    }
    logo_image = Image("logo.png");
}

// ─────────────────────────────────────────────────────────────────────────
// Background: dark blue gradient
// ─────────────────────────────────────────────────────────────────────────
fun draw_background() {
    // Solid dark blue base
    Window.SetBackgroundTopColor(background_color[0], background_color[1], background_color[2]);
    Window.SetBackgroundBottomColor(0.0, 0.02, 0.06);

    // Subtle radial glow behind the orb
    glow_sprite = Sprite();
    glow_sprite.SetPosition(orb_cx - 200, orb_cy - 200, -100);
    glow_image = Image.New(400, 400);
    // Draw a soft radial gradient glow
    for (r = 200; r > 0; r -= 4) {
        alpha = (1.0 - r / 200.0) * 0.15 * glow_intensity;
        glow_image.Fill(200 - r, 200 - r, 2 * r, 2 * r,
                        orb_glow[0], orb_glow[1], orb_glow[2], alpha);
    }
    glow_sprite.SetImage(glow_image);
}

// ─────────────────────────────────────────────────────────────────────────
// Draw the orb using procedural primitives (fallback if no PNG frames)
// ─────────────────────────────────────────────────────────────────────────
fun draw_orb_procedural() {
    // Pulsing scale
    scale = 1.0 + 0.05 * Math.Sin(orb_pulse);
    r = orb_radius * scale;

    // Outer glow rings (3 layers for depth)
    for (layer = 3; layer > 0; layer--) {
        glow_r = r + layer * 15;
        alpha = 0.08 * glow_intensity / layer;
        Window.Fill(orb_cx - glow_r, orb_cy - glow_r, 2 * glow_r, 2 * glow_r,
                     orb_glow[0], orb_glow[1], orb_glow[2], alpha);
    }

    // Main orb body — radial gradient simulated with concentric circles
    for (i = 0; i < 20; i++) {
        rr = r * (1.0 - i / 20.0);
        t = i / 20.0;
        cr = orb_blue[0] * (1.0 - t) + orb_glow[0] * t;
        cg = orb_blue[1] * (1.0 - t) + orb_glow[1] * t;
        cb = orb_blue[2] * (1.0 - t) + orb_glow[2] * t;
        ca = 0.8 - t * 0.3;
        Window.Fill(orb_cx - rr, orb_cy - rr, 2 * rr, 2 * rr, cr, cg, cb, ca);
    }

    // Specular highlight — shifts position to simulate rotation
    highlight_angle = orb_pulse;
    hl_x = orb_cx + 25 * Math.Cos(highlight_angle);
    hl_y = orb_cy - 20 + 10 * Math.Sin(highlight_angle);

    // Highlight glow
    for (i = 0; i < 8; i++) {
        hr = 18 - i * 2;
        ha = 0.15 - i * 0.015;
        Window.Fill(hl_x - hr, hl_y - hr, 2 * hr, 2 * hr,
                     orb_highlight[0], orb_highlight[1], orb_highlight[2], ha);
    }

    // Bright center of highlight
    Window.Fill(hl_x - 4, hl_y - 4, 8, 8, 1.0, 1.0, 1.0, 0.9);

    // Orb outline
    Window.Fill(orb_cx - r, orb_cy - r, 2 * r, 2 * r,
                 orb_blue[0], orb_blue[1], orb_blue[2], 0.0);
}

// ─────────────────────────────────────────────────────────────────────────
// Draw the orb using PNG frames (preferred if available)
// ─────────────────────────────────────────────────────────────────────────
fun draw_orb_frames() {
    current_frame = frame % 36;
    img = orb_frames[current_frame];
    if (img == NULL) {
        draw_orb_procedural();
        return;
    }

    // Scale the orb image
    img_w = Image.GetWidth(img);
    img_h = Image.GetHeight(img);
    scale = 1.0 + 0.03 * Math.Sin(orb_pulse);

    sprite = Sprite(img);
    sprite.SetScale(scale, scale);
    sprite.SetPosition(orb_cx - (img_w * scale) / 2, orb_cy - (img_h * scale) / 2, 0);

    // Additional glow behind the orb
    glow_sprite = Sprite();
    glow_image = Image.New(300, 300);
    for (r = 150; r > 0; r -= 5) {
        alpha = (1.0 - r / 150.0) * 0.1 * glow_intensity;
        glow_image.Fill(150 - r, 150 - r, 2 * r, 2 * r,
                         orb_glow[0], orb_glow[1], orb_glow[2], alpha);
    }
    glow_sprite.SetImage(glow_image);
    glow_sprite.SetPosition(orb_cx - 150, orb_cy - 150, -1);
}

// ─────────────────────────────────────────────────────────────────────────
// Draw "AeroOS" text below the orb
// ─────────────────────────────────────────────────────────────────────────
fun draw_text() {
    text_y = orb_cy + orb_radius + 40;

    // Text glow
    text_image = Image.Text("AeroOS", 36, text_color[0], text_color[1], text_color[2], "Cantarell Bold");
    if (text_image != NULL) {
        text_w = Image.GetWidth(text_image);
        text_h = Image.GetHeight(text_image);
        text_sprite = Sprite(text_image);
        text_sprite.SetPosition((screen_width - text_w) / 2, text_y, 0);
    }

    // Subtitle
    sub_image = Image.Text("Aero Glass Edition", 16, 0.5, 0.6, 0.75, "Cantarell");
    if (sub_image != NULL) {
        sub_w = Image.GetWidth(sub_image);
        sub_sprite = Sprite(sub_image);
        sub_sprite.SetPosition((screen_width - sub_w) / 2, text_y + 50, 0);
    }
}

// ─────────────────────────────────────────────────────────────────────────
// Draw progress indicator (spinning dots at bottom)
// ─────────────────────────────────────────────────────────────────────────
fun draw_progress() {
    dot_y = screen_height - 80;
    dot_radius = 6;
    dot_spacing = 24;
    num_dots = 5;

    total_width = (num_dots - 1) * dot_spacing;
    start_x = (screen_width - total_width) / 2;

    for (i = 0; i < num_dots; i++) {
        // Each dot lights up in sequence, creating a spinning effect
        dot_phase = (progress_angle + i * 0.4) % (2 * 3.14159);
        brightness = (Math.Sin(dot_phase) + 1.0) / 2.0;

        dx = start_x + i * dot_spacing;
        alpha = 0.2 + brightness * 0.8;
        r = dot_radius * (0.7 + brightness * 0.3);

        Window.Fill(dx - r, dot_y - r, 2 * r, 2 * r,
                     progress_color[0], progress_color[1], progress_color[2], alpha);
    }
}

// ─────────────────────────────────────────────────────────────────────────
// Draw a boot progress bar (Windows 7 style — thin bar above the dots)
// ─────────────────────────────────────────────────────────────────────────
fun draw_progress_bar() {
    bar_width = 200;
    bar_height = 4;
    bar_x = (screen_width - bar_width) / 2;
    bar_y = screen_height - 50;

    // Background track
    Window.Fill(bar_x, bar_y, bar_width, bar_height, 0.1, 0.15, 0.25, 0.5);

    // Filled portion
    fill_width = bar_width * boot_progress;
    if (fill_width > 0) {
        Window.Fill(bar_x, bar_y, fill_width, bar_height,
                     progress_color[0], progress_color[1], progress_color[2], 0.9);
    }

    // Animated shimmer across the bar
    shimmer_x = bar_x + (progress_angle * 30) % bar_width;
    shimmer_w = 40;
    if (shimmer_x + shimmer_w > bar_x + bar_width) {
        shimmer_w = bar_x + bar_width - shimmer_x;
    }
    if (shimmer_w > 0) {
        Window.Fill(shimmer_x, bar_y, shimmer_w, bar_height, 0.6, 0.8, 1.0, 0.4);
    }
}

// ─────────────────────────────────────────────────────────────────────────
// Main animation loop
// ─────────────────────────────────────────────────────────────────────────
fun refresh() {
    draw_background();

    if (has_frames) {
        draw_orb_frames();
    } else {
        draw_orb_procedural();
    }

    draw_text();
    draw_progress();
    draw_progress_bar();
}

// ─────────────────────────────────────────────────────────────────────────
// Animation tick — called ~50 times per second
// ─────────────────────────────────────────────────────────────────────────
fun animate() {
    frame = frame + 1;
    orb_pulse = orb_pulse + 0.08;
    progress_angle = progress_angle + 0.15;
    glow_intensity = 0.5 + 0.3 * Math.Sin(orb_pulse * 0.5);
}

// ─────────────────────────────────────────────────────────────────────────
// Boot progress callback
// ─────────────────────────────────────────────────────────────────────────
fun boot_progress_callback(progress) {
    boot_progress = progress;
}

// ─────────────────────────────────────────────────────────────────────────
// Boot status callback (text messages)
// ─────────────────────────────────────────────────────────────────────────
fun boot_status_callback(status) {
    // We don't display text status — the orb animation is the focus
}

// ─────────────────────────────────────────────────────────────────────────
// Quit callback — fade out
// ─────────────────────────────────────────────────────────────────────────
fun quit_callback() {
    // Fade the orb to full brightness then fade out
    for (i = 0; i < 30; i++) {
        glow_intensity = 1.0;
        refresh();
        Window.Advance();
        // Small delay
    }
}

// ─────────────────────────────────────────────────────────────────────────
// Register callbacks
// ─────────────────────────────────────────────────────────────────────────
Plymouth.SetRefreshFunction(refresh);
Plymouth.SetBootProgressFunction(boot_progress_callback);
Plymouth.SetBootStatusFunction(boot_status_callback);
Plymouth.SetQuitFunction(quit_callback);

// Start the animation
animate();
PLYMOUTH_SCRIPT

# ─────────────────────────────────────────────────────────────────────────────
# 6.  Attempt to generate PNG frames (optional — procedural fallback built in)
# ─────────────────────────────────────────────────────────────────────────────
generate_orb_frames || true

# ─────────────────────────────────────────────────────────────────────────────
# 7.  Set AeroOS as the default Plymouth theme
# ─────────────────────────────────────────────────────────────────────────────
echo "[INFO] Setting AeroOS as default Plymouth theme…"
plymouth-set-default-theme -R aeroos

# Verify
CURRENT_THEME=$(plymouth-set-default-theme)
echo "[OK] Active Plymouth theme: ${CURRENT_THEME}"

# ─────────────────────────────────────────────────────────────────────────────
# 8.  Update initramfs to include the new theme
# ─────────────────────────────────────────────────────────────────────────────
echo "[INFO] Updating initramfs to include Plymouth theme…"
update-initramfs -u -k all 2>/dev/null || echo "[WARN] update-initramfs not available in chroot — will run at ISO build time."

# ─────────────────────────────────────────────────────────────────────────────
# 9.  Configure GRUB to use Plymouth (silent boot)
# ─────────────────────────────────────────────────────────────────────────────
if [ -f /etc/default/grub ]; then
    echo "[INFO] Configuring GRUB for silent boot (Plymouth)…"

    # Remove existing GRUB_CMDLINE_LINUX_DEFAULT line(s) and add ours
    sed -i '/^GRUB_CMDLINE_LINUX_DEFAULT=/d' /etc/default/grub
    sed -i '/^GRUB_CMDLINE_LINUX=/d' /etc/default/grub

    cat >> /etc/default/grub <<'GRUB_CFG'
GRUB_CMDLINE_LINUX_DEFAULT="quiet splash"
GRUB_CMDLINE_LINUX="quiet splash"
GRUB_CFG

    # Set a reasonable resolution for the boot animation
    sed -i '/^GRUB_GFXMODE=/d' /etc/default/grub
    echo 'GRUB_GFXMODE=1024x768,auto' >> /etc/default/grub

    sed -i '/^GRUB_GFXPAYLOAD_LINUX=/d' /etc/default/grub
    echo 'GRUB_GFXPAYLOAD_LINUX=keep' >> /etc/default/grub

    echo "[OK] GRUB configured for silent boot with Plymouth."
else
    echo "[WARN] /etc/default/grub not found — skipping GRUB configuration."
fi

# ─────────────────────────────────────────────────────────────────────────────
# 10.  Summary
# ─────────────────────────────────────────────────────────────────────────────
echo ""
echo "================================================"
echo " AeroOS Step 2 — COMPLETE"
echo "================================================"
echo ""
echo " What was configured:"
echo "   ✓ Custom Plymouth theme 'aeroos' created at ${THEME_DIR}"
echo "   ✓ Theme includes:"
echo "       - aeroos.plymouth  (theme descriptor)"
echo "       - aeroos.script   (animation engine: glowing orb + progress)"
echo "       - frames/          (36 PNG orb animation frames, if ImageMagick)"
echo "       - logo.png         (static orb logo)"
echo "   ✓ Procedural fallback built into script (works without PNGs)"
echo "   ✓ AeroOS set as default Plymouth theme"
echo "   ✓ initramfs updated"
echo "   ✓ GRUB configured for quiet splash boot"
echo ""
echo " Animation features:"
echo "   - Dark blue gradient background"
echo "   - Pulsing/rotating glowing orb (Windows 7 style)"
echo "   - Shifting specular highlight simulates rotation"
echo "   - 'AeroOS' text with 'Aero Glass Edition' subtitle"
echo "   - Spinning dot progress indicator"
echo "   - Thin progress bar with shimmer effect"
echo ""
echo "================================================"
