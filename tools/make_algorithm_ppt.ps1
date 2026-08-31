param(
    [string]$OutputPath = ""
)

$ErrorActionPreference = "Stop"

if ([string]::IsNullOrWhiteSpace($OutputPath)) {
    $repo = Split-Path -Parent $PSScriptRoot
    $OutputPath = Join-Path $repo "docs\Quest_Avatar_Placement_Algorithm.pptx"
}
$OutputPath = [System.IO.Path]::GetFullPath($OutputPath)
[System.IO.Directory]::CreateDirectory([System.IO.Path]::GetDirectoryName($OutputPath)) | Out-Null

function Rgb([int]$r, [int]$g, [int]$b) { return $r + 256 * $g + 65536 * $b }

$C = @{
    Navy   = Rgb 16 42 67
    Ink    = Rgb 22 50 79
    Blue   = Rgb 25 118 210
    Cyan   = Rgb 44 177 188
    Green  = Rgb 39 174 96
    Orange = Rgb 245 158 11
    Red    = Rgb 228 87 86
    Purple = Rgb 113 82 173
    Light  = Rgb 245 248 252
    Pale   = Rgb 232 240 248
    White  = Rgb 255 255 255
    Muted  = Rgb 92 112 132
    Line   = Rgb 200 214 226
    Dark   = Rgb 32 44 55
}

function Add-Text($slide, [string]$text, [double]$x, [double]$y, [double]$w, [double]$h,
                  [double]$size = 20, [int]$color = $C.Ink, [bool]$bold = $false,
                  [int]$align = 1, [int]$valign = 1) {
    $shape = $slide.Shapes.AddTextbox(1, $x, $y, $w, $h)
    $shape.TextFrame2.MarginLeft = 0
    $shape.TextFrame2.MarginRight = 0
    $shape.TextFrame2.MarginTop = 0
    $shape.TextFrame2.MarginBottom = 0
    $shape.TextFrame2.VerticalAnchor = $valign
    $shape.TextFrame2.TextRange.Text = $text
    $shape.TextFrame2.TextRange.ParagraphFormat.Alignment = $align
    $shape.TextFrame2.TextRange.Font.Name = "Aptos"
    $shape.TextFrame2.TextRange.Font.Size = $size
    $shape.TextFrame2.TextRange.Font.Bold = $(if ($bold) { -1 } else { 0 })
    $shape.TextFrame2.TextRange.Font.Fill.ForeColor.RGB = $color
    return $shape
}

function Add-Box($slide, [string]$text, [double]$x, [double]$y, [double]$w, [double]$h,
                 [int]$fill, [int]$textColor = $C.White, [double]$size = 17,
                 [bool]$bold = $true, [int]$lineColor = -1) {
    $shape = $slide.Shapes.AddShape(5, $x, $y, $w, $h)
    $shape.Fill.Solid()
    $shape.Fill.ForeColor.RGB = $fill
    $shape.Line.ForeColor.RGB = $(if ($lineColor -ge 0) { $lineColor } else { $fill })
    $shape.Line.Weight = 1.25
    $shape.TextFrame2.MarginLeft = 10
    $shape.TextFrame2.MarginRight = 10
    $shape.TextFrame2.MarginTop = 5
    $shape.TextFrame2.MarginBottom = 5
    $shape.TextFrame2.VerticalAnchor = 3
    $shape.TextFrame2.TextRange.Text = $text
    $shape.TextFrame2.TextRange.ParagraphFormat.Alignment = 2
    $shape.TextFrame2.TextRange.Font.Name = "Aptos"
    $shape.TextFrame2.TextRange.Font.Size = $size
    $shape.TextFrame2.TextRange.Font.Bold = $(if ($bold) { -1 } else { 0 })
    $shape.TextFrame2.TextRange.Font.Fill.ForeColor.RGB = $textColor
    return $shape
}

function Add-Arrow($slide, [double]$x1, [double]$y1, [double]$x2, [double]$y2,
                   [int]$color = $C.Blue, [double]$weight = 2.5) {
    $line = $slide.Shapes.AddConnector(1, $x1, $y1, $x2, $y2)
    $line.Line.ForeColor.RGB = $color
    $line.Line.Weight = $weight
    $line.Line.EndArrowheadStyle = 3
    return $line
}

function Add-Circle($slide, [string]$text, [double]$x, [double]$y, [double]$d,
                    [int]$fill, [int]$textColor = $C.White, [double]$size = 15) {
    $shape = $slide.Shapes.AddShape(9, $x, $y, $d, $d)
    $shape.Fill.Solid(); $shape.Fill.ForeColor.RGB = $fill
    $shape.Line.ForeColor.RGB = $fill
    $shape.TextFrame2.VerticalAnchor = 3
    $shape.TextFrame2.TextRange.Text = $text
    $shape.TextFrame2.TextRange.ParagraphFormat.Alignment = 2
    $shape.TextFrame2.TextRange.Font.Name = "Aptos"
    $shape.TextFrame2.TextRange.Font.Size = $size
    $shape.TextFrame2.TextRange.Font.Bold = -1
    $shape.TextFrame2.TextRange.Font.Fill.ForeColor.RGB = $textColor
    return $shape
}

function New-Slide($presentation, [string]$title, [string]$kicker = "CURRENT QUEST RUNTIME") {
    $slide = $presentation.Slides.Add($presentation.Slides.Count + 1, 12)
    $slide.FollowMasterBackground = 0
    $slide.Background.Fill.Solid()
    $slide.Background.Fill.ForeColor.RGB = $C.Light
    [void](Add-Text $slide $kicker 42 22 600 22 10 $C.Blue $true)
    [void](Add-Text $slide $title 42 48 865 46 28 $C.Navy $true)
    $bar = $slide.Shapes.AddShape(1, 42, 101, 876, 3)
    $bar.Fill.Solid(); $bar.Fill.ForeColor.RGB = $C.Cyan; $bar.Line.Visible = 0
    return $slide
}

function Add-Footer($slide, [int]$number, [string]$source) {
    [void](Add-Text $slide $source 42 511 770 15 8 $C.Muted $false)
    [void](Add-Text $slide ([string]$number) 872 507 46 18 9 $C.Muted $true 3)
}

$ppt = $null
$presentation = $null
try {
    $ppt = New-Object -ComObject PowerPoint.Application
    $ppt.Visible = -1
    $ppt.DisplayAlerts = 1
    $presentation = $ppt.Presentations.Add()
    $presentation.PageSetup.SlideWidth = 960
    $presentation.PageSetup.SlideHeight = 540

    # 1 — Title
    $s = $presentation.Slides.Add(1, 12)
    $s.FollowMasterBackground = 0
    $s.Background.Fill.Solid(); $s.Background.Fill.ForeColor.RGB = $C.Navy
    [void](Add-Text $s "QUEST ARUCO AVATAR" 54 60 850 42 16 $C.Cyan $true)
    [void](Add-Text $s "How the avatar is placed\non the mannequin" 54 112 760 105 36 $C.White $true)
    [void](Add-Text $s "Current detection, reconstruction, rest and filtering algorithm" 56 229 780 34 18 (Rgb 204 222 238) $false)
    $labels = @("CAMERA", "MARKERS", "COMMON POSE", "FILTER", "AVATAR")
    $fills = @($C.Blue, $C.Cyan, $C.Green, $C.Orange, $C.Purple)
    for ($i=0; $i -lt 5; $i++) {
        $x = 58 + $i * 174
        [void](Add-Box $s $labels[$i] $x 330 144 62 $fills[$i] $C.White 15 $true)
        if ($i -lt 4) { [void](Add-Arrow $s ($x+144) 361 ($x+170) 361 $C.White 2) }
    }
    [void](Add-Text $s "Project snapshot • 30 August 2026" 56 472 500 18 10 (Rgb 170 194 216) $false)

    # 2 — Objective and frames
    $s = New-Slide $presentation "The placement problem"
    [void](Add-Text $s "Three physical markers must describe one virtual body anchor." 42 124 700 30 20 $C.Ink $true)
    [void](Add-Circle $s "ID0\ncommon" 72 204 95 $C.Blue)
    [void](Add-Circle $s "ID1\nchest" 72 326 95 $C.Cyan)
    [void](Add-Circle $s "ID2\ntorso" 210 326 95 $C.Green)
    [void](Add-Arrow $s 170 250 376 278 $C.Muted 2.5)
    [void](Add-Arrow $s 170 370 376 306 $C.Muted 2.5)
    [void](Add-Arrow $s 305 370 376 314 $C.Muted 2.5)
    [void](Add-Box $s "ONE COMMON\n6-DoF POSE" 378 246 180 95 $C.Navy $C.White 20 $true)
    [void](Add-Text $s "Pose = position (X,Y,Z) + orientation" 610 198 300 34 18 $C.Navy $true)
    [void](Add-Text $s "The calibration stores a full marker → common transform, including both translation and rotation." 610 249 286 92 16 $C.Ink $false)
    [void](Add-Box $s "marker world pose × marker-to-common offset = common estimate" 604 365 300 68 $C.Pale $C.Ink 15 $true $C.Line)
    Add-Footer $s 2 "navel_provider.gd • default_navel_calibration.cfg"

    # 3 — Camera timing
    $s = New-Slide $presentation "From camera pixels to marker poses"
    $xs = @(48, 232, 416, 600, 784)
    $txt = @("Quest\ncamera frame", "Head pose from\n≈50 ms earlier", "OpenCV detects\nvisible IDs", "Same timestamp\nfor one result", "Marker poses\nin world space")
    $fill = @($C.Blue,$C.Purple,$C.Cyan,$C.Orange,$C.Green)
    for ($i=0; $i -lt 5; $i++) {
        [void](Add-Box $s $txt[$i] $xs[$i] 205 132 86 $fill[$i] $C.White 15 $true)
        if ($i -lt 4) { [void](Add-Arrow $s ($xs[$i]+132) 248 ($xs[$i+1]-10) 248 $C.Muted 2.2) }
    }
    [void](Add-Text $s "Why use the earlier head pose?" 52 340 300 28 18 $C.Navy $true)
    [void](Add-Text $s "The pixels were captured in the past. Combining them with the live head pose would make markers swim when the user moves their head." 52 375 420 78 15 $C.Ink $false)
    [void](Add-Text $s "Worker rule" 540 340 160 28 18 $C.Navy $true)
    [void](Add-Text $s "Only the newest pending image is processed. Older unprocessed frames are dropped to avoid an expanding queue." 540 375 355 78 15 $C.Ink $false)
    Add-Footer $s 3 "main_3d.gd • CAMERA_LATENCY_MS = 50"

    # 4 — Marker fusion
    $s = New-Slide $presentation "Reconstruct and fuse the common pose"
    [void](Add-Text $s "Only markers from the exact newest camera result are combined." 42 122 760 28 18 $C.Ink $true)
    $rows = @(
        @("1 marker", "Use its reconstructed common pose", $C.Blue),
        @("2 markers", "Mean position + sign-aligned quaternion average", $C.Cyan),
        @("3 markers", "Coordinate median + quaternion medoid", $C.Green)
    )
    for ($i=0; $i -lt 3; $i++) {
        $y=176+$i*76
        [void](Add-Box $s $rows[$i][0] 54 $y 150 54 $rows[$i][2] $C.White 16 $true)
        [void](Add-Box $s $rows[$i][1] 222 $y 430 54 $C.White $C.Ink 15 $false $C.Line)
    }
    [void](Add-Box $s "Outlier example\n100, 102, 160 mm\n\nMean = 120.7 mm\nMedian = 102 mm" 700 170 204 198 (Rgb 255 242 225) $C.Dark 16 $true $C.Orange)
    [void](Add-Text $s "Average is steadier when all three are good; robust fusion is safer when one ArUco pose is corrupted. The experiment should compare mean, robust and agreement-checked mean." 54 430 842 54 14 $C.Muted $false)
    Add-Footer $s 4 "navel_provider.gd::_fuse"

    # 5 — Startup rest
    $s = New-Slide $presentation "Startup: learn a robust session rest pose"
    [void](Add-Text $s "The avatar stays hidden while independent fused poses are collected." 42 122 780 28 18 $C.Ink $true)
    $counts = @(20,25,30,35)
    $names = @("E0","E1","E2","E3")
    for ($i=0; $i -lt 4; $i++) {
        $x=74+$i*205
        [void](Add-Circle $s ([string]$counts[$i]) $x 205 72 $(if($i -eq 3){$C.Green}else{$C.Blue}) $C.White 18)
        [void](Add-Text $s $names[$i] ($x+10) 284 52 24 15 $C.Navy $true 2)
        if ($i -lt 3) { [void](Add-Arrow $s ($x+72) 241 ($x+190) 241 $C.Muted 2.4) }
    }
    [void](Add-Text $s "Each E uses coordinate-median position + quaternion-medoid rotation over all collected poses." 70 329 820 30 16 $C.Ink $false 2)
    [void](Add-Box $s "Stable comparison\nΔ position ≤ 2 mm  AND  Δ rotation ≤ 0.5°" 96 387 370 70 $C.Pale $C.Ink 16 $true $C.Line)
    [void](Add-Box $s "3 stable comparisons → detection 35\n≈8 s earliest\nDetection 50 fallback ≈11.4 s" 500 387 366 70 (Rgb 231 247 237) $C.Dark 15 $true $C.Green)
    Add-Footer $s 5 "navel_provider.gd • 2.0 mm / 0.50° are present in the grid, but not yet validated as best"

    # 6 — Runtime filter
    $s = New-Slide $presentation "After startup: the runtime filter"
    $items = @(
        @("1", "NEW FUSED\nMEASUREMENT", $C.Blue),
        @("2", "7-POSE\nMEDOID", $C.Cyan),
        @("3", "DEAD\nZONES", $C.Green),
        @("4", "EXPONENTIAL\nSMOOTHING", $C.Orange),
        @("5", "LOCAL REST\nPULL", $C.Purple)
    )
    for ($i=0;$i -lt 5;$i++) {
        $x=43+$i*181
        [void](Add-Circle $s $items[$i][0] ($x+50) 150 36 $items[$i][2] $C.White 13)
        [void](Add-Box $s $items[$i][1] $x 205 140 74 $items[$i][2] $C.White 14 $true)
        if($i -lt 4){[void](Add-Arrow $s ($x+140) 242 ($x+174) 242 $C.Muted 2.2)}
    }
    [void](Add-Text $s "Updates once per new OpenCV timestamp" 45 317 200 50 14 $C.Muted $false 2)
    [void](Add-Text $s "Rejects a lone temporal outlier" 226 317 200 50 14 $C.Muted $false 2)
    [void](Add-Text $s "Holds tiny position / rotation changes" 407 317 200 50 14 $C.Muted $false 2)
    [void](Add-Text $s "Moves continuously at render rate" 588 317 200 50 14 $C.Muted $false 2)
    [void](Add-Text $s "Only near remembered rest" 769 317 150 50 14 $C.Muted $false 2)
    [void](Add-Box $s "Current values: window 7 • position dead zone 6 mm • rotation dead zone 0.5° • smoothing τ = 0.8 s • prior τ = 8 s" 94 410 772 55 $C.Navy $C.White 16 $true)
    Add-Footer $s 6 "simple_pose_stabilizer.gd • avatar_rig_navel.gd"

    # 7 — Medoid
    $s = New-Slide $presentation "Why the seven-pose medoid rejects jumps"
    $dots = @(
        @(128,230),@(166,218),@(194,252),@(232,224),@(258,262),@(286,235),@(420,168)
    )
    for($i=0;$i -lt $dots.Count;$i++){
        $fill = $(if($i -eq 6){$C.Red}elseif($i -eq 3){$C.Green}else{$C.Blue})
        $label = $(if($i -eq 6){"bad"}elseif($i -eq 3){"chosen"}else{"M$($i+1)"})
        [void](Add-Circle $s $label $dots[$i][0] $dots[$i][1] 54 $fill $C.White 11)
    }
    [void](Add-Text $s "Six measurements agree; one is far away. The medoid chooses the actual measured pose with the smallest total distance to all others." 70 344 430 88 17 $C.Ink $false)
    [void](Add-Box $s "score = position distance\n+ radius × rotation angle" 570 184 310 80 $C.Pale $C.Ink 18 $true $C.Line)
    [void](Add-Text $s "Current radius = 0.2864789 m\n\nAt this radius, 1° rotation contributes approximately the same score as 5 mm of position error." 574 294 302 118 16 $C.Ink $false)
    Add-Footer $s 7 "simple_pose_stabilizer.gd::_medoid • radius is included in the tuning grid"

    # 8 — Dead zone, smoothing, prior
    $s = New-Slide $presentation "Dead zone, smoothing and prior do different jobs"
    $cards = @(
        @("DEAD ZONE", "≤6 mm position\n≤0.5° rotation\n\nHold the corresponding output channel.", $C.Green),
        @("SMOOTHING", "τ = 0.8 s\n\n63% after 0.8 s\n86.5% after 1.6 s\n95% after 2.4 s", $C.Orange),
        @("REST PRIOR", "τ = 8 s\n\nActive during normal tracking; only confirmed relocation suspends it.", $C.Purple)
    )
    for($i=0;$i -lt 3;$i++){
        $x=54+$i*302
        [void](Add-Box $s $cards[$i][0] $x 150 264 48 $cards[$i][2] $C.White 17 $true)
        [void](Add-Box $s $cards[$i][1] $x 210 264 190 $C.White $C.Ink 16 $false $C.Line)
    }
    [void](Add-Text $s "The 6 mm / 0.5° display dead zones never switch off the prior. Relocation uses separate persistent-movement thresholds." 82 438 795 44 15 $C.Navy $true 2)
    Add-Footer $s 8 "Filtering order: medoid → dead zones → smoothing → state-controlled rest pull"

    # 9 — Relocation state machine
    $s = New-Slide $presentation "Movement uses a separate relocation state machine"
    [void](Add-Box $s "Measurement-only\n7-pose medoid" 70 180 210 82 $C.Cyan $C.White 18 $true)
    [void](Add-Arrow $s 280 221 405 221 $C.Muted 3)
    [void](Add-Box $s "Large offset persists?\n100 mm / 5° provisional" 407 180 170 82 $C.Orange $C.White 15 $true)
    [void](Add-Arrow $s 577 221 700 221 $C.Muted 3)
    [void](Add-Box $s "Suspend moved channel\nuntil endpoint stable" 702 180 190 82 $C.Purple $C.White 16 $true)
    [void](Add-Text $s "Stable endpoint → re-anchor rest → prior resumes" 235 302 490 30 21 $C.Navy $true 2)
    [void](Add-Text $s "Position and rotation are independent. Candidate samples must persist, and settling uses separate 2 mm / 0.5° stability limits—not the display dead zone." 120 355 720 65 16 $C.Ink $false 2)
    [void](Add-Box $s "600-second healing has been removed from the new runtime." 210 440 540 44 (Rgb 255 242 225) $C.Dark 14 $true $C.Orange)
    Add-Footer $s 9 "simple_pose_stabilizer.gd relocation state • navel_provider.gd re-anchor"

    # 10 — Loss and resume
    $s = New-Slide $presentation "Tracking loss and Quest-menu resume"
    [void](Add-Text $s "Temporary marker loss" 58 140 360 30 21 $C.Navy $true)
    [void](Add-Box $s "No new marker result\nfor 300 ms" 62 192 180 74 $C.Red $C.White 16 $true)
    [void](Add-Arrow $s 242 229 302 229 $C.Muted 2.5)
    [void](Add-Box $s "Hide avatar\nkeep last internal pose" 304 192 180 74 $C.Purple $C.White 16 $true)
    [void](Add-Arrow $s 394 266 394 326 $C.Muted 2.5)
    [void](Add-Box $s "Collect 7 fresh detections\n≈1.6 s at 4.4 Hz" 304 330 180 74 $C.Green $C.White 15 $true)
    [void](Add-Text $s "App resumes after Quest menu" 548 140 350 30 21 $C.Navy $true)
    [void](Add-Box $s "Old XR world rest\nmay no longer be valid" 562 192 180 74 $C.Red $C.White 16 $true)
    [void](Add-Arrow $s 742 229 802 229 $C.Muted 2.5)
    [void](Add-Box $s "Keep permanent\nmarker offsets" 804 192 120 74 $C.Blue $C.White 15 $true)
    [void](Add-Arrow $s 742 266 742 326 $C.Muted 2.5)
    [void](Add-Box $s "Relearn startup rest\n35–50 detections\n≈8–11.4 s" 652 330 180 74 $C.Orange $C.White 15 $true)
    Add-Footer $s 10 "marker_freshness.gd • avatar_rig_navel.gd::_notification"

    # 11 — Final placement
    $s = New-Slide $presentation "Final render transform"
    [void](Add-Box $s "FILTERED\nCOMMON POSE" 72 195 190 86 $C.Green $C.White 19 $true)
    [void](Add-Text $s "×" 302 213 40 48 32 $C.Navy $true 2)
    [void](Add-Box $s "FIXED MODEL\nALIGNMENT" 380 195 190 86 $C.Purple $C.White 19 $true)
    [void](Add-Text $s "=" 610 213 40 48 32 $C.Navy $true 2)
    [void](Add-Box $s "VISIBLE\nAVATAR" 690 195 190 86 $C.Blue $C.White 19 $true)
    [void](Add-Box $s "Scale 0.77\nRotation −90° X (lay flat)\nPosition (0.07256, −0.127499, 0.177248) m" 340 334 280 100 $C.White $C.Ink 16 $false $C.Line)
    [void](Add-Text $s "The removed −30° shoulder roll is no longer present." 250 458 460 24 16 $C.Green $true 2)
    [void](Add-Text $s "A persistent fixed offset here cannot be repaired by waiting, smoothing, the prior or relocation re-anchoring." 62 130 835 36 17 $C.Red $true 2)
    Add-Footer $s 11 "main_3d.tscn: mannequin child transform • AvatarRig.global_transform = filtered pose"

    # 12 — Parameter provenance
    $s = New-Slide $presentation "What the experiment must decide"
    [void](Add-Text $s "The grid contains the current values; being present in a grid does not mean the experiment has selected them as best." 42 120 865 42 17 $C.Ink $true)
    $headerY=183
    $colX=@(50,315,590,780)
    $colW=@(250,260,175,130)
    $heads=@("Parameter group","Examples in grid","Current","Status")
    for($i=0;$i -lt 4;$i++){[void](Add-Box $s $heads[$i] $colX[$i] $headerY $colW[$i] 40 $C.Navy $C.White 13 $true)}
    $tableRows=@(
        @("Startup convergence","2.0 mm × 0.50° included","2 mm / 0.5°","Provisional"),
        @("Display filter","window, dead zone, smoothing","7 / 6 mm / 0.8 s","Provisional"),
        @("Prior / relocation","2–30 s; 20–150 mm; 2–15°","8 s; 100 mm; 5°","Provisional"),
        @("Fusion strategy","mean / robust / agreement mean","robust for 3","Not yet compared")
    )
    for($r=0;$r -lt $tableRows.Count;$r++){
        $y=$headerY+44+$r*56
        for($i=0;$i -lt 4;$i++){
            $fill=$(if($r%2 -eq 0){$C.White}else{$C.Pale})
            $color=$(if($i -eq 3 -and $r -eq 3){$C.Red}else{$C.Ink})
            [void](Add-Box $s $tableRows[$r][$i] $colX[$i] $y $colW[$i] 50 $fill $color 12 $(if($i -eq 3){$true}else{$false}) $C.Line)
        }
    }
    [void](Add-Box $s "Required evidence: labelled stationary recording + known movement recording + error plots" 105 463 750 42 $C.Cyan $C.White 15 $true)
    Add-Footer $s 12 "tune_filter.py • current values must not be called experimentally validated yet"

    # 13 — NaReT project requirement
    $s = New-Slide $presentation "How this prototype supports NaReT"
    [void](Add-Box $s "NARET REQUIREMENT" 55 142 245 48 $C.Navy $C.White 17 $true)
    [void](Add-Box $s "German–Polish AI/XR learning\nthrough realistic resuscitation scenarios" 55 204 245 118 $C.White $C.Ink 17 $true $C.Line)
    [void](Add-Arrow $s 300 263 372 263 $C.Muted 3)
    [void](Add-Box $s "QUEST PROTOTYPE" 374 142 212 48 $C.Blue $C.White 17 $true)
    [void](Add-Box $s "Place and stabilize the virtual patient\non the real CPR mannequin" 374 204 212 118 $C.White $C.Ink 17 $true $C.Line)
    [void](Add-Arrow $s 586 263 658 263 $C.Muted 3)
    [void](Add-Box $s "TECHNICAL METHOD" 660 142 245 48 $C.Purple $C.White 17 $true)
    [void](Add-Box $s "ArUco markers, calibration,\npose fusion and filtering" 660 204 245 118 $C.White $C.Ink 17 $true $C.Line)
    [void](Add-Box $s "Important: NaReT requires a reliable XR learning experience. It does not prescribe ArUco markers or a particular barcode size." 94 375 772 62 (Rgb 255 242 225) $C.Dark 16 $true $C.Orange)
    [void](Add-Text $s "Project method: concept → prototype → testing → evaluation → iterative improvement" 102 458 755 28 17 $C.Navy $true 2)
    Add-Footer $s 13 "Sources: NaReT JEMS A1.5 • About the project / O projekcie"

    # 14 — Immediate order
    $s = New-Slide $presentation "What to do next — in the correct order"
    $steps=@(
        @("1", "SAVE BASELINE", "Clean the working tree; commit and push the current 10 cm working version.", $C.Navy),
        @("2", "TEST SMALL MARKERS", "Keep IDs 0/1/2 and DICT_4X4_50; compare 10, 7.5 and 5 cm.", $C.Blue),
        @("3", "FINALIZE TRACKING", "Choose size, recalibrate, tune the filter and produce one clean APK.", $C.Purple),
        @("4", "VALIDATE CPR", "Run the complete BLS scenario, not only an avatar-visibility test.", $C.Green)
    )
    for($i=0;$i -lt $steps.Count;$i++){
        $y=134+$i*88
        [void](Add-Circle $s $steps[$i][0] 66 ($y+7) 52 $steps[$i][3] $C.White 18)
        [void](Add-Text $s $steps[$i][1] 136 $y 225 28 16 $steps[$i][3] $true)
        [void](Add-Text $s $steps[$i][2] 365 $y 520 49 15 $C.Ink $false)
        if($i -lt 3){[void](Add-Arrow $s 92 ($y+59) 92 ($y+81) $C.Muted 2)}
    }
    Add-Footer $s 14 "The barcode experiment begins only after the current working version is recoverable from GitHub"

    # 15 — Small-marker experiment
    $s = New-Slide $presentation "Small-marker experiment — change one thing at a time"
    $sizes=@(
        @("10 cm", "CONTROL", $C.Green),
        @("7.5 cm", "FIRST CANDIDATE", $C.Blue),
        @("5 cm", "SMALLEST CANDIDATE", $C.Orange)
    )
    for($i=0;$i -lt 3;$i++){
        $x=75+$i*294
        [void](Add-Box $s $sizes[$i][0] $x 145 220 72 $sizes[$i][2] $C.White 25 $true)
        [void](Add-Text $s $sizes[$i][1] $x 227 220 24 13 $sizes[$i][2] $true 2)
    }
    [void](Add-Text $s "For every size" 60 286 180 28 20 $C.Navy $true)
    [void](Add-Box $s "Print exact black-square size\n+ clear white border" 60 330 190 82 $C.White $C.Ink 14 $true $C.Line)
    [void](Add-Arrow $s 250 371 282 371 $C.Muted 2)
    [void](Add-Box $s "Set aruco_patch_size\n+ recalibrate mounting" 284 330 190 82 $C.White $C.Ink 14 $true $C.Line)
    [void](Add-Arrow $s 474 371 506 371 $C.Muted 2)
    [void](Add-Box $s "Record labelled\nCPR-view tests" 508 330 190 82 $C.White $C.Ink 14 $true $C.Line)
    [void](Add-Arrow $s 698 371 730 371 $C.Muted 2)
    [void](Add-Box $s "Compare reliability\nand alignment" 732 330 170 82 $C.White $C.Ink 14 $true $C.Line)
    [void](Add-Text $s "Measure: detection rate • longest loss • position/rotation wobble • alignment error • recovery" 65 450 830 34 15 $C.Navy $true 2)
    Add-Footer $s 15 "Keep dictionary, IDs, resolution and filter fixed while marker size changes"

    # 16 — CPR acceptance test
    $s = New-Slide $presentation "The complete CPR acceptance test"
    $flow=@(
        @("1", "Safety"), @("2", "Response"), @("3", "Call 112"), @("4", "Breathing"),
        @("5", "Compress"), @("6", "AED"), @("7", "Resume"), @("8", "Handover")
    )
    for($i=0;$i -lt $flow.Count;$i++){
        $row=[math]::Floor($i/4); $col=$i%4
        $x=45+$col*228; $y=145+$row*132
        [void](Add-Circle $s $flow[$i][0] $x ($y+10) 48 $(if($row -eq 0){$C.Blue}else{$C.Green}) $C.White 16)
        [void](Add-Box $s $flow[$i][1] ($x+58) $y 140 68 $C.White $C.Ink 16 $true $C.Line)
        if($col -lt 3){[void](Add-Arrow $s ($x+198) ($y+34) ($x+222) ($y+34) $C.Muted 2)}
    }
    [void](Add-Box $s "Quest tracking must remain usable throughout the sequence" 180 396 600 48 $C.Navy $C.White 18 $true)
    [void](Add-Text $s "Acceptance: no random fly-in • correct orientation • acceptable wobble • loss recovery • real mannequin movement retained" 65 466 830 35 15 $C.Ink $true 2)
    Add-Footer $s 16 "Scenario 1 // Lernplattform • medical content must be approved by the project medical partners"

    # 17 — Product completion
    $s = New-Slide $presentation "From technical prototype to NaReT deliverable"
    $cols=@(
        @("CONTENT", "German + Polish\nProductive vs receptive phrases\nAudio + pronunciation\nAED and Situation B", $C.Blue),
        @("QUALITY", "Usability + accessibility\nPhone/tablet/desktop\nPrivacy decisions\nReliable Quest tracking", $C.Purple),
        @("EVIDENCE", "Structured user tests\nQuantitative + qualitative evaluation\nIterative corrections\nProject documentation", $C.Green)
    )
    for($i=0;$i -lt 3;$i++){
        $x=50+$i*303
        [void](Add-Box $s $cols[$i][0] $x 144 265 48 $cols[$i][2] $C.White 17 $true)
        [void](Add-Box $s $cols[$i][1] $x 204 265 185 $C.White $C.Ink 15 $false $C.Line)
    }
    [void](Add-Box $s "Current Drive priorities: platform skeleton • language minigames • privacy • audio/speech • AED scope • Situation B • responsive UI • documentation" 75 432 810 60 $C.Cyan $C.White 15 $true)
    Add-Footer $s 17 "Source: NaReT Action Items board (read-only GitHub export) • JEMS A1.5 and A1.7"

    $presentation.SaveAs($OutputPath, 24)
    Write-Output "Created: $OutputPath"
    Write-Output "Slides: $($presentation.Slides.Count)"
}
finally {
    if ($presentation -ne $null) { $presentation.Close() }
    if ($ppt -ne $null) { $ppt.Quit() }
    if ($presentation -ne $null) { [void][System.Runtime.InteropServices.Marshal]::ReleaseComObject($presentation) }
    if ($ppt -ne $null) { [void][System.Runtime.InteropServices.Marshal]::ReleaseComObject($ppt) }
    [GC]::Collect()
    [GC]::WaitForPendingFinalizers()
}
