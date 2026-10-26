# Tracking, OpenXR und Quest-Export

Die App verwendet den bestehenden OpenCV-Detektor aus `godot-opencv-aruco`. Der Adapter implementiert keine eigene Marker-Erkennung. Die Filterung und Handpositionsprüfung stammen aus `quest-aruco-avatar`, Branch `apk-filtering-handtracking`. OpenXR Vendors ist als drittes Submodul eingebunden, weil `~/dev/godot_openxr_vendors` auf diesem Rechner nicht vorhanden war.

## Gepinnte Abhängigkeiten

| Abhängigkeit | Revision | Verwendung / Lizenz |
|---|---|---|
| [NaReT/godot-opencv-aruco](https://github.com/NaReT-Nachbarsprache-wird-reanimiert/godot-opencv-aruco) | `2f07af7b6ecd0d8b6b97ec1ffd9f11646084fdce` | CameraServer, WorkerThreadPool, OpenCVProcessor, Marker-Pose; Unlicense |
| [quest-aruco-avatar](https://github.com/ardrabauldwin/quest-aruco-avatar/tree/apk-filtering-handtracking) | `1560fee6bf766f4dae98f5025155b14476b75877` | SimplePoseStabilizer, CPRHandZone, CPRMotionSession; Unlicense |
| [Godot OpenXR Vendors](https://github.com/GodotVR/godot_openxr_vendors/releases/tag/5.1.0-stable) | `7afcd397e6206d9751b82100559ff39a93a8f59e` | Vendor-Erweiterungen, originale Hand-/Controller-Skripte; MIT-Wrapper mit mitgelieferten Plattform-Lizenzhinweisen |

OpenXR Vendors enthält zusätzlich `meta/LICENSE-SDK` und `meta/LICENSE-LOADER`. Der MIT-Status des Wrappers ersetzt diese SDK-/Loader-Bedingungen nicht. Die OpenCV- und übrigen transitiven Lizenzen bleiben in ihren jeweiligen Quellen erhalten.

## Installation

Godot **4.7 oder neuer** ist für die aktuelle CameraServer-Variante erforderlich; lokal wurde Godot **4.7.2** verwendet. Ein frischer Clone enthält die Quellen und den gepinnten Android-Debug-Detektor, aber noch kein macOS-ArUco-Framework.

```sh
git submodule update --init --recursive
python3 tools/setup_dependencies.py --download-vendors
```

Der Download ist auf Vendors `5.1.0-stable` mit SHA256 `6a838dbdf4115549e4511ebee0da9a5dcc8f9f6258d4cc2f2ee57a907a3e2911` festgelegt. Bereits vorhandene ZIP-Dateien lassen sich über `--vendor-zip DATEI` verwenden. Generierte Addons unter `addons/` sind ignoriert; die Submodule werden beim Staging nicht verändert. Ohne gebauten Host-Detektor bleibt die Desktop-Vorschau nutzbar.

Die Android-Vorlage kann Godot über „Projekt → Android-Build-Vorlage installieren“ anlegen. Alternativ mit der **zur Engine passenden** bereits heruntergeladenen Vorlage:

```sh
python3 tools/setup_dependencies.py --android-template \
  "$HOME/Library/Application Support/Godot/export_templates/4.7.2.stable/android_source.zip"
```

Das Skript erzeugt `android/.gdignore` und setzt das Ausführungsrecht für `gradlew`. Ein vorhandener Build-Baum wird beibehalten. In den Godot-Editor-Einstellungen müssen Android-SDK und Java SDK 17 gesetzt sein.

### Native Bibliotheken bauen

SCons, Conan und das passende Android-NDK müssen installiert sein. Das aktuelle ArUco-Submodul nutzt das NDK `23.2.8568313` und sein eingechecktes Conan-Android-Profil. Die Android-Exportvorlage von Godot selbst kann ein neueres NDK benötigen; das ist ein eigener Build-Schritt. Das kleine NaReT-Buildprofil enthält alle vom Detektor verwendeten Klassen, einschließlich `ProjectSettings`, das im upstream Beispielprofil fehlt.

Vom Projektverzeichnis aus:

```sh
scons -C third_party/godot-opencv-aruco platform=macos arch=arm64 \
  target=template_debug build_profile=../../tools/aruco_build_profile.json -j8

ANDROID_HOME="$HOME/Library/Android/sdk" \
ANDROID_NDK_ROOT="$HOME/Library/Android/sdk/ndk/23.2.8568313" \
scons -C third_party/godot-opencv-aruco platform=android arch=arm64 \
  target=template_debug build_profile=../../tools/aruco_build_profile.json -j8

python3 tools/setup_dependencies.py --aruco
```

Auf anderen Hosts wird `platform=linux` beziehungsweise `platform=windows` und die richtige Architektur verwendet. `--aruco` aktiviert das Addon ausdrücklich; vor einem macOS-Import muss deshalb das Host-Framework vorhanden sein. Für einen Release-Export muss zusätzlich `target=template_release` für die benötigten Plattformen gebaut und erneut gestaged werden. `check_quest.py --release` lehnt fehlende Release-Bibliotheken ab.

### APK erstellen

```sh
python3 tools/check_quest.py
godot --headless --xr-mode off --path . --editor --export-debug "Meta Quest 3" build/naret-quest.apk
python3 tools/check_quest.py --device
adb install -r build/naret-quest.apk
```

Der Preset exportiert ausschließlich ARM64 und aktiviert Meta OpenXR, Handtracking, Passthrough, Internet, Mikrofon, `android.permission.CAMERA` und `horizonos.permission.HEADSET_CAMERA`. Package-ID: `de.uni_greifswald.naret.mannequinxr`. Der ArUco-Export-Guard wird beim Staging aktiviert. Unter macOS verhindert `--xr-mode off` bei Headless-Tests den Versuch, ein lokales OpenXR-Headset zu initialisieren; im APK bleibt OpenXR über die Projekteinstellung aktiv.

## Marker und Kalibrierung

Der echte Detektor verwendet **DICT_4X4_50**, IDs 0–49. Der mitgelieferte Marker ist `assets/textures/markers/aruco_4x4_50_0.png`; keine 3×3-Marker verwenden. Die physische Seitenlänge des schwarzen Markerquadrats muss dem Inspector-Wert `marker_size_m` entsprechen (Standard 0,05 m). Das Papier beziehungsweise der weiße Rand zählt nicht zur Markergröße.

`NaretArucoTracker` instanziiert den originalen `ArucoMarkerTracking`-Node, sobald `OpenCVProcessor` verfügbar ist und die App auf Android läuft. Alternativ lässt sich ein vorhandener Provider über `provider_path` oder `bind_provider()` verbinden. Er muss `get_marker_world_pose(id)` und `marker_age_ms(id)` sowie das Signal `markers_updated(ids)` anbieten. Die API ist direkt an der aktuellen Upstream-Implementierung geprüft. Der Detektor veröffentlicht außerdem weiterhin die standardmäßigen `OpenXRMarkerTracker` im `XRServer`.

Die wesentliche Verbindung lautet:

```gdscript
tracker.pose_updated.connect(anchor.update_pose)
tracker.set_view_camera(xr_camera)
interaction.configure(mannequin, xr_origin)
interaction.register_ui_panel(panel_mesh, subviewport, Vector2(0.8, 1.0))
```

`pose_updated(Transform3D)` liefert **Weltkoordinaten**. `NaretSpatialAnchor` multipliziert `marker_world * marker_to_mannequin`. Ein zusätzliches Anwenden von XROrigin oder Referenzrahmen wäre falsch. Die Kalibrierung speichert nur den relativen Offset, einschließlich begrenzter Skalierung, in `user://calibration.cfg`; sie behauptet keinen zwischen Sitzungen persistenten OpenXR-Weltanker. `calibrate(mannequin_world_pose)` berechnet den Offset aus der aktuell beobachteten Markerpose. Nach dem nächsten Scan wird er wieder angewendet.

Ein Marker gilt nach 500 ms als verloren; die letzte Pose bleibt stehen, aber `tracked` wird `false`. Desktop-Preview emittiert eine explizite Vorschaupose und setzt `tracked` niemals auf `true`. Nach einer erfassten Pose pausiert die Detektion außerhalb des Kamerafrustums; beim Zurückschauen startet sie wieder. Hand-Eye-Kalibrierung, Linsenparameter und Kamera-Latenzkorrektur bleiben im Upstream-Backend. Die dortigen Quest-3-Parameter müssen für das konkrete Headset, dessen Feed und die tatsächliche Markergröße überprüft werden.

`tracker.configure_marker(size_m, marker_id)` setzt die physische Markergröße und ID zur Laufzeit und speichert sie in der Sektion `marker` derselben Kalibrierungsdatei. Gültig sind 0,01–0,30 m und IDs 0–49. Eine Änderung verwirft die alte Filterhistorie und ein möglicherweise noch laufendes Detektionsergebnis; die letzte Darstellung bleibt bis zur Neuerfassung stehen. Marker- und Puppen-Offset-Einstellungen bleiben bei gegenseitigem Speichern erhalten.

### Marker auf dem Brustbein (puppenunabhängig)

Der virtuelle Patient wird ohne Scan und ohne Vermessung auf **jede** Übungspuppe gelegt. Einziger Bezugspunkt ist ein Marker auf dem Druckpunkt:

- **Aufkleben:** Mittelpunkt des Markers auf die untere Hälfte des Brustbeins (Druckpunkt), flach, am besten auf einem kleinen festen Träger (4–5 cm), nicht über eine Rundung gebogen.
- **Achsen:** Marker +Y ist die Brustnormale, Marker −Z zeigt zum Kopf der Puppe. Die Oberkante des gedruckten Markers zeigt also zum Kopf. Das ist aus dem Code abgeleitet und muss einmal auf dem Gerät bestätigt werden. Liegt der Patient verdreht, korrigiert der Gier-Regler im Kalibrierpanel das und wird gespeichert.
- **Ohne Kalibrierung** berechnet `NaretSpatialAnchor.sternum_offset()` den Offset aus dem `sternum`-Knoten des Patienten und `marker_thickness_m` (Standard 2 mm): Das virtuelle Brustbein liegt genau unter dem Marker, die Brustneigung folgt der Markernormale. Eine gespeicherte Kalibrierung (`calibrated = true`) hat Vorrang; „Zurücksetzen“ stellt wieder den Brustbein-Offset her.
- **Der Marker bleibt während der CPR liegen.** Hände verdecken ihn, und er sinkt mit jeder Kompression 5–6 cm ein. Deshalb folgt der Patient dem Marker nur, bis eine Pose `SETTLE_MS` (1,5 s) lang innerhalb von 1 cm / 4° ruhig war. Diese gemittelte Pose wird festgehalten (`locked`). Danach gilt:
  - Kompressionen und verdeckte Frames ändern nichts, denn ein Fenster, in dem der Marker wippt, kommt nie zur Ruhe.
  - Das Eindrücken zeigt nur der Brustkorb selbst (`set_compression_depth`).
  - Eine neue ruhige Pose, die mehr als 1,5 cm / 5° abweicht, legt den Patienten neu an. Das bedeutet: Die Puppe wurde verschoben.
  - `unlock()` erzwingt Neuerfassung.
- **Genauigkeit:** exakt am Druckpunkt, sonst nur ungefähr. Schulterbreite, Wölbung und Halslänge der Puppe werden nicht gemessen. Die Genauigkeit hängt an Markergröße, Kamera und Handtracking (etwa 1 cm).
- **Desktop/Simulator:** Die Vorschaupose ist die Pose, die der Marker auf dem Brustbein hätte (`preview_pose = Patientenort * marker_to_mannequin⁻¹`). Der Patient steht dort wie bisher.

## Hände, Interaktion und CPR

`NaretOpenXRSetup` verwendet den nativen OpenXR-Start, Alpha-Passthrough und das originale Vendor-Skript `hand_mesh.gd`. Laufzeit-Handmeshes werden über `OpenXRFbHandTrackingMesh` und `XRHandModifier3D` aufgebaut; `hand` wird erst nach dem Einhängen in den Baum gesetzt, weil die Vendor-Erweiterung ihre Knochen erst dort benennt.

**Es gibt keinen Controller-Pfad.** `XRController3D` wird nicht mehr gebunden, es existieren keine Button-Handler und keine Controller-Rays. `hand_tracker()` verwirft jede Hand, deren `hand_tracking_source` `CONTROLLER` oder `NOT_TRACKED` ist — ein gehaltener Controller macht die Hand damit stumm statt zweideutig. Es gibt zwei Auswahlwege, wie in MRTK: **Nah** pokt die Fingerspitze das Panel direkt — ab 6 cm Abstand übernimmt sie den Zeiger, ab 5 mm vor der Fläche drückt sie, ab 15 mm löst sie wieder aus; solange gepokt wird, verschwindet der Strahl dieser Hand. **Fern** läuft über einen Strahl aus der Handfläche entlang der Kopf-zu-Handfläche-Richtung, ausgelöst per Pinch mit validierten Daumen-/Zeigefingerpositionen und 22/35-mm-Hysterese. Press und Release werden über eine Zeiger-Erfassung zusammengehalten, auch wenn Hand oder Finger zwischendurch abrutschen. Die Hand, die gerade das Menü trägt, sendet keinen Strahl.

Die Projekteinstellungen aktivieren dafür `meta/hand_tracking_mesh` (ohne die Einstellung baut der Vendor-Knoten gar kein Skelett, und die Handmeshes bleiben unsichtbar), `meta/anchor_api`, `meta/scene_api` sowie das `hand_interaction_profile`; `hand_tracking_controller_data_source` ist bewusst **aus**.

`NaretHandMenu` dockt das Bedienpanel über der linken Hand an, sobald deren Handfläche zum Kopf zeigt (Hysterese 0,55 / 0,30 im Skalarprodukt), und blendet es beim Wegdrehen wieder aus. Es gibt kein Fenster: Die Szenario-Aktionen schweben als Hex-Knoten über den Fingerspitzen (Zeige- bis Kleinfinger, Überlauf auf der Manschette), ein gewölbtes Diagnosepanel liegt auf der Handfläche (Zustand, EKG-Spur, 30:2-Zähler) und eine Manschette am Unterarm trägt Sprache, Modus, Mikrofon, Kalibrierung und Export. Testhilfen öffnet die Taste „Debug“ unter „Training starten“ als eigene Reihe, die bis zum zweiten Druck offen bleibt: Marker-Gizmos (rohe erkannte Markerposen als Achsenkreuze, vor Layout und Patientenversatz), Meta-Handmeshes, Referenzscan und Tiefenverdeckung. Alle Elemente hängen an getrackten Gelenken (Palm, Wrist, Fingerspitzen) und sind eigene 3D-Ziele (`register_ui_panel` ohne Viewport), die `pointer_hover(depth_m)`/`pointer_press(down)` direkt erhalten; ein Knoten löst zusätzlich aus, wenn der Daumen derselben Hand die Fingerspitze berührt (2,5 cm an, 3,5 cm aus). Farben folgen dem Corporate Design (NaReT-Blau `#1f3c7b`, NaReT-Rot `#d11909`). `make menu-shot` rendert die Hand ohne Headset. Die Handfläche zeigt entlang **+Z** des Palm-Gelenks — dieselbe Konvention, auf der schon die CPR-Zone beruht — und das Gelenk muss dafür gültige Orientierungsflags liefern, nicht nur eine Position.

`NaretRoomLayout` liest den Meta-Raumscan über `OpenXRFbSceneManager` (`auto_create`, unsichtbar). Aus dem `floor`-Anker kommt `get_boundary_2d()` als Raumumriss, aus Möbelankern `get_bounding_box_3d()` als achsparallele Grundfläche. `pick_spots()` ist reine Geometrie und ohne Headset testbar: Umriss um 45 cm einwärts versetzt (`Geometry2D.offset_polygon`), Möbel um 35 cm aufgeweitet, Kandidaten auf Ringen von 1,4 bis 2,6 m um den Patienten, mindestens 90 cm Abstand untereinander. Ohne Scan liefert sie eine leere Liste, und die Szene behält ihre Standardpositionen. Der APK deklariert dafür `com.oculus.permission.USE_SCENE`.

Die Handposition wird vom bestehenden `cpr_hand_zone.gd` geprüft: Handballen-Schätzung aus Wrist/Palm, zum Brustkorb orientierte Handfläche und gestapelte Hände. Fehlende oder vom Controller synthetisierte Gelenke gelten nicht als optisch gemessene Handposition. Die Zone folgt `mannequin.get_sternum_transform()`; das Standardmodell liegt mit +Y nach oben und Kopf nach −Z.

**`compression_measured(depth_m, rate_bpm, correct_position)` liefert Handbewegung als Proxy, keine kalibrierte Brustkorb-Drucktiefe.** Sichtverdeckung, Handflächenmodell und räumliche Kalibrierung begrenzen die Aussagekraft. Der erste Hub liefert BPM 0, weil noch kein Intervall vorhanden ist. Für eine belastbare Drucktiefe ist ein instrumentiertes Mannequin beziehungsweise ein separat validierter Sensor nötig. Die App kennzeichnet diese Daten mit `measurement_source = "hand_motion_proxy"`.

Der Upstream-Hubdetektor wird unverändert verwendet. Das Setup ergänzt dessen generierte Kopie reproduzierbar um drei Konfigurationsschalter: `automatic_breathing_pause`, `require_metronome_alignment` und `metronome_enabled`. NaReT deaktiviert diese drei Standalone-Demo-Regeln. Damit zählt der Detektor vollständige Hübe unabhängig vom Metronom; der Szenario-Controller besitzt allein den 30:2-Ablauf. Der Patch prüft seine vier genauen Quelltextstellen und bricht bei einer unerwarteten Upstream-Änderung ab. `set_cpr_enabled()` aktiviert die Übung; `rearm_cpr_cycle()` setzt die Bewegungsbasis nach einer expliziten Beatmungspause zurück.

`set_aed_active(true)` überwacht unabhängig davon die Nähe getrackter Hände am ganzen Patienten und emittiert `patient_contact`, um eine zuvor bestätigte AED-Freigabe ungültig zu machen. Nicht erkannte Nähe beweist keine Kontaktfreiheit; die explizite Freigabe bleibt erforderlich.

## Nachgewiesene Prüfungen und Gerätegrenzen

Native Android-ARM64-Debug- und macOS-ARM64-Debug-Builds wurden lokal erfolgreich mit SCons erstellt. Die Godot-Testsuiten einschließlich der Kalibrierungsmatrix, echten Provider-Schnittstelle, Tracking-Verlust und der Trennung von Hubdetektor/Szenario laufen mit:

```sh
godot --headless --xr-mode off --path . --script tests/run_tests.gd
```

72 FPS, Marker-Genauigkeit, tatsächliche Kamerafreigabe und Handtracking-Qualität sind Geräte-Messungen. Ein erfolgreicher Desktop-Test oder APK-Export ersetzt diese nicht. Das native Addon macht GPU→CPU-Readback und danach eine Worker-Aufgabe; die hier gesetzte halbe Bildauflösung reduziert die Arbeit, kann aber kleine oder entfernte Marker schlechter erkennen.

Das vorhandene `mannequin.glb` aus dem Avatar-Submodul lässt sich über `--upstream-model` unverändert als `mannequin_upstream.glb` kopieren. Die Hauptszene verwendet dessen normalisierten texturierten Scan `mannequin_scan.glb`; Details und Provenienz stehen in [MODELS.md](MODELS.md). Die Repo-Lizenz ist Unlicense; eine separate Modell-Provenienz ist im Submodul nicht dokumentiert.
