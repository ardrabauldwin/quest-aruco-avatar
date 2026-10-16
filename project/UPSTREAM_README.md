# NaReT · Mannequin XR

Bilinguales Reanimationstraining für **Meta Quest 3**, gebaut mit **Godot 4.7.2, OpenXR und GDScript**. Erwachsene BLS-Simulation nach den ERC-Leitlinien 2025: Reaktion prüfen, sofort 112, dann Atmung prüfen, AED holen lassen, 30:2, AED-Analyse, sichere Schockabgabe, sofortige weitere CPR und Übergabe. Oberfläche und Anweisungen sind Deutsch/Polnisch; Angehörige sprechen die jeweilige Nachbarsprache.

**Die APK liegt nach dem Build unter `build/naret-quest.apk`.** Sie enthält die Quest-ARM64-Bibliotheken, OpenXR, Offline-Audio und die Szenen. Ein erfolgreicher Export ist kein Nachweis für Marker-Genauigkeit oder 72 FPS auf dem Headset. Auf Wunsch wurde in dieser Sitzung keine Installation auf der Quest vorgenommen.

## Am Mac starten

```sh
git submodule update --init --recursive
python3 tools/setup_dependencies.py --download-vendors
godot --headless --xr-mode off --path . --editor --import --quit
python3 tools/run_local.py --xr-mode off
```

`run_local.py` liest den vorhandenen Schlüssel aus `.env` (`API_SECRET` oder `UNI_API_KEY`) und reicht ihn ausschließlich über die Prozessumgebung an Godot weiter. Die Datei wird weder eingecheckt noch in die APK exportiert. Ein Start direkt über den Editor funktioniert auch ohne Schlüssel im Offline-Modus.

```sh
python3 tools/run_local.py --offline --xr-mode off
```

Die Android-/XR-Erweiterung benötigt die passende native Bibliothek; ohne Host-Build bleibt die Desktop-Vorschau nutzbar. Das originale ArUco-Backend wird nicht nachimplementiert. [Native Builds und Dependency-Staging](docs/TRACKING.md) erklären den Unterschied zwischen Desktop-Vorschau und Kamera-Tracking.

## Bedienung / Obsługa

**Auf der Quest wird ausschließlich mit Handtracking bedient.** Controller sind nicht gebunden: Sobald eine Hand einen Controller hält, meldet die Laufzeit sie als controllergeführt, und NaReT ignoriert sie vollständig. Leg die Controller weg.

| Aktion | Desktop | Quest (nur Hände) |
|---|---|---|
| Menü öffnen | immer sichtbar | Linke Handfläche zum Gesicht drehen — das Menü dockt über der Hand an |
| Trainingsschritt | Schaltfläche | Schaltfläche mit dem Zeigefinger antippen, oder aus der Ferne zeigen und pinchen |
| Kompression simulieren | `C` / Schaltfläche | Optisch verfolgte, gestapelte Hände an der Druckzone |
| Beatmung simulieren | `V` / Schaltfläche | Schaltfläche im Handmenü |
| Mit Angehörigen sprechen | Text + Enter; `T` | Einfach sprechen — das Mikrofon nimmt selbst auf |
| Mikrofon scharf/stumm | Mikrofontaste | Mikrofontaste im Handmenü |
| Sprache wechseln | DE / PL | DE / PL im Handmenü |
| Modus wechseln | Modustaste in der Kopfzeile | Modustaste im Handmenü |
| Ansicht drehen / zoomen | Leere Fläche ziehen / Mausrad | Kopfbewegung |
| Kalibrieren | „Kalibrieren“ | ⊹ im Handmenü |
| QCPR-Simulator steuern | `F2` / „QCPR-Sim“ | Live-Werte auf Patientenanzeige |
| Explizite ROSC-Demonstration | „Trainer“ / `F8`, erst nach AED und weiterer CPR | Reguläre Übung über Übergabe beenden |

Das Handmenü trägt nur Bedienelemente. Anweisung, Angehörigen-Dialog und EKG stehen auf einer eigenen Anzeige am Kopfende des Patienten, damit sie während der Kompressionen lesbar bleiben, wenn beide Hände auf dem Brustkorb liegen.

## Zwei Modi: erst die eigene Sprache

Nach dem didaktischen Modell der [NaReT-Lernplattform](https://github.com/NaReT-Nachbarsprache-wird-reanimiert) kommt der Ablauf vor der Sprache:

| Modus | Anweisungen | Angehörige sprechen | Zweck |
|---|---|---|---|
| **Eigene Sprache** (Standard) | Sprache des Lernenden | dieselbe Sprache | Handlungswissen aufbauen, ohne fremdsprachliche Last |
| **Nachbarsprache** | Sprache des Lernenden | die jeweils andere Sprache | Derselbe, nun bekannte Ablauf mit der Nachbarsprache |

Der klinische Ablauf ist in beiden Modi identisch — nur die Sprache der Angehörigen wechselt. Damit ist im zweiten Modus die Sprache die einzige neue Variable. Beide Modi funktionieren offline, weil für DE und PL dieselben zehn Sprachclips vorliegen.

## Automatische Mikrofonaufnahme

Das Mikrofon nimmt selbstständig auf, sobald jemand spricht — bei Kompressionen liegen beide Hände auf dem Brustkorb, da lässt sich keine Taste halten. Die Erkennung ist aus der Lernplattform übernommen (`SpeakGame.tsx`): Effektivwert über **0,02** startet die Aufnahme, **1,2 s** Stille danach beendet sie, mindestens **0,5 s** Sprache, spätestens nach **12 s**. Während die Angehörigen sprechen oder eine Transkription läuft, ist die Erkennung blockiert, damit die App nicht sich selbst aufnimmt.

Der Schwellwert hängt von Raum und Mikrofon ab. Bei lauter Umgebung oder Fehlauslösern ist `VAD_THRESHOLD` in [audio_manager.gd](scripts/ai/audio_manager.gd) die Stellschraube. Die Mikrofontaste schaltet die Erkennung scharf oder stumm; Offline-ASR gibt es weiterhin nicht.

## Angehörige im echten Raum

Die beiden Angehörigen werden über den **Raumscan der Quest** (Meta Scene API) auf freien Boden gestellt: mindestens 45 cm Wandabstand, 35 cm Abstand zu erfassten Möbeln, 90 cm untereinander, in 1,4–2,6 m Ring um den Patienten, jeweils zu ihm gewandt. Bewegt sich der Marker um mehr als 40 cm, werden sie neu platziert.

Ein frisch aufgesetztes Headset beantwortet die Layout-Abfrage leer, bevor es sich im Raum lokalisiert hat. NaReT fragt deshalb rund 30 Sekunden lang nach und meldet erst dann „kein Raumscan". Die systemeigene Raumeinrichtung startet die App **nicht** von selbst — jemanden mitten aus einer laufenden Reanimation in einen Scan-Dialog zu ziehen wäre schlimmer als die hinterlegte Standardplatzierung. Ohne Scan (oder ohne Scene API) bleiben die Positionen aus der Szene aktiv; der Raumscan ist Komfort, keine Voraussetzung. Richte den Raum bei Bedarf in den Quest-Einstellungen unter „Physischer Raum" ein und starte NaReT neu. Der Scan wird ausschließlich gelesen; NaReT schreibt keine Anker und speichert keine Raumgeometrie.

Wybierz **PL**, aby uruchomić polskie instrukcje. Anna odpowiada po niemiecku. Bez połączenia z chmurą używaj przycisków i tekstu; lokalne nagrania nadal działają. Skan manekina służy do kalibracji 1:1, a animowany człowiek jest osobnym modelem.

Das Training bestätigt bei Schaltflächen nur eingegebene Schritte. Die angezeigte Handbewegung ist eine **Schätzung**, keine kalibrierte Drucktiefe. Ein Schock erzeugt niemals automatisch ROSC. PEA, VF, Asystolie und die hier simulierte pulslose VT erzeugen keinen mechanischen Herzschlag. [Ablauf, Messgrenzen und Quellen](docs/BLS.md).

## Szenen und Modelle

- `scenes/main.tscn`: Desktop- und XR-Komposition, Shared API Client, Szenario, Tracking, EKG, Feedback.
- `scenes/mannequin.tscn`: animierter digitaler Patient, separates Herz, Pupillen, Brustkorb und Kontaktzonen.
- `scenes/bystander.tscn`: Angehörige mit Sprach- und Emotionsanimation.
- `scenes/ui/`: EKG und eine Nachbesprechung mit tatsächlich bestätigten Schritten, Zeitpunkten und Fehlern.

Der **Scan der realen Übungspuppe dient ausschließlich als zuschaltbare Referenz für den 1:1-Abgleich**. Er ist vom riggbaren menschlichen Digitalzwilling getrennt. Seine native Größe bleibt erhalten; die Gesichtspunkte sind illustrative Modellmarkierungen. [Scan-Provenienz und Aufbereitung](docs/MODELS.md), [Architektur](docs/ARCHITECTURE.md).

## Uni-Cloud und Offline-Modus

Die App verwendet die OpenAI-kompatiblen REST-Endpunkte der Uni Greifswald mit HTTPS und Bearer-Auth. Keine KI-Modelle laufen auf der Quest.

| Dienst | Angefordertes Modell | Tatsächlicher Godot-Test am Mac |
|---|---|---|
| ASR | `large-v3` | 975 ms, Transkript erhalten |
| LLM | `unsloth/Qwen3.8-27B-GGUF:Q4_K_M` | DE 1392 ms / PL 1089 ms, gültiges Dialog-JSON |
| TTS | `omnivoice` | DE 1174 ms / PL 829 ms, Audio erfolgreich dekodiert |

**Omnivoice ist vorhanden und funktioniert.** Bei diesem Server muss das optionale `voice`-Feld entfallen; `voice="alloy"` erzeugte HTTP 500. Die Messungen sind einzelne Funktionstests, keine Latenzgarantie. Das gewünschte TTS-Ziel von unter 500 ms wurde im Godot-Test nicht erreicht. [Sanitisierter Testbericht](docs/godot_api_probe.json), [API-Details](docs/API.md).

Requests laufen asynchron, mit höchstens zwei Sekunden Timeout pro Dienst. Die Gesamtzeit ASR → LLM → TTS kann entsprechend länger sein. Der LLM-Client begrenzt Starts auf mindestens 500 ms Abstand, verarbeitet eine begrenzte Queue und verwirft alte Antworten nach Sprachwechsel/Neustart. Modellaktionen können keine AED-Schocks oder Vitaländerungen auslösen. Deterministisch erkannte Rufe nach 112/AED können die entsprechenden Kommunikationsschritte bestätigen.

Vorgenerierte Sprachclips (Fish Audio S2 Pro) in DE/PL sind enthalten und werden lokal abgespielt. Bei Cloud-Ausfall funktionieren Textdialog und Schaltflächen weiter; **Offline-ASR ist nicht enthalten**. Statische Anweisungen spielen sofort lokal. Untertitel folgen bei TTS-Ausfall dem tatsächlich abgespielten Ersatzclip. `tools/generate_voices_fish.py` erneuert sie, `tools/check_voices.py` prüft sie per Whisper.

## APK bauen und später installieren

Benötigt: Godot 4.7.2 samt passenden Exportvorlagen, Android SDK, JDK 17, gepinnte Vendors-Erweiterung und ArUco-ARM64-Debug-Bibliothek. Das Setup kann eine vorhandene Android-Quellvorlage installieren:

```sh
python3 tools/setup_dependencies.py --download-vendors --aruco \
  --android-template "$HOME/Library/Application Support/Godot/export_templates/4.7.2.stable/android_source.zip"
make apk
python3 tools/audit_apk.py
```

Bei einem frischen Mac muss vor `--aruco` zunächst das Host-Framework gebaut werden; siehe [TRACKING.md](docs/TRACKING.md). Für Release-Builds wird zusätzlich die native `template_release`-Bibliothek benötigt. Die mitgelieferte Konfiguration erzeugt eine **signierte Debug-APK**, kein Store-Release.

Für die spätere Verwendung: Quest-Entwicklermodus aktivieren, USB-Debugging am Headset bestätigen, Quest und Uni-Cloud über geeignetes WLAN verbinden. Dann:

```sh
adb install -r build/naret-quest.apk
python3 tools/configure_quest.py
adb shell am start -n de.uni_greifswald.naret.mannequinxr/com.godot.game.GodotAppLauncher
```

`configure_quest.py` schreibt die API-Konfiguration erst nach der Installation in den privaten App-Speicher. Der Schlüssel ist **nicht in der APK**. `--dry-run` zeigt den Ablauf ohne Gerätezugriff, `--offline` entfernt den Schlüssel aus dieser App-Konfiguration. Nach Änderungen die App neu starten. Kamera-, Headset-Kamera- und Mikrofonfreigaben müssen auf der Quest erteilt werden.

## QCPR-Puppen-Integration und Smart-Puppen-Simulator

NaReT integriert eine modulare Abstraktionsschicht (`NaretQcprBackend`) für QCPR-kompatible Trainingspuppen über das CPRM-Protokoll (Bluetooth Low Energy). Da smarte Trainingspuppen nicht immer physisch verfügbar sind, enthält NaReT einen **vollständigen Smart-Puppen-Simulator auf Protokollebene** mit physiologischem Physik-Modell und automatischer Ersatzschaltung (Auto-Fallback).

### Smart-Puppen-Simulator (`SimulatedManikinBackend`)

Der Simulator verhält sich auf Protokollebene exakt wie eine reale Trainingspuppe:
- **Identische Protokollstrukturen:** Binäre CPRM-Frames (`[MsgId][SeqNo][Params]`, Little-Endian) mit denselben Message-IDs (`CP_WAVE` 192, `CP_EVENT` 193, `CP_RATE` 194, `CP_INACTIVITY` 195, `QF_*` 224–228, `SC_SECURITY_CODE` 232, `QS_DATA` 208).
- **Authentifizierungs-Handshake:** CPRM-Sicherheitsschlüssel (18 Bytes) und Bestätigungssequenz.
- **Physik-Modell:** Realistische asymmetrische Kompressionskurve (38 % Druckphase, 62 % Rückstellphase), Drucktiefe 0–65 mm, Frequenz 80–150 bpm, Inaktivitätserkennung und konfigurierbares physiologisches Signalrauschen.
- **ERC 2021 Leitlinienkonformität:** Erwachsene Zielwerte von 50–60 mm Tiefe und 100–120/min Frequenz werden verifiziert und für den Session-Score ausgewertet.

#### Szenario-Presets:
1. **Gute CPR (ERC 2021):** Zieltiefe 55 mm, Frequenz 110/min, vollständige Entlastung.
2. **Zu flach:** 38 mm Drucktiefe (< 50 mm), löst `QF_COMP_SHALLOW` aus.
3. **Zu langsam:** 75/min (< 100/min), löst `QF_COMP_SLOW` aus.
4. **Zu schnell:** 138/min (> 120/min), löst `QF_COMP_FAST` aus.
5. **Unvollständige Entlastung:** 12 mm Resttiefe (Leaning), löst `QF_INCOMP_RELEASE` aus.
6. **Erschöpfung:** Dynamisches Szenario — nach 10 Sekunden sinkt die Leistung über 40 Sekunden allmählich von 112 auf 82/min und von 55 auf 36 mm ab (Rescuer Fatigue).

#### Steuerung des Simulators:
- **Debug-Panel:** Über die Schaltfläche `QCPR-Sim` in der Kopfzeile oder per Tastendruck auf `F2` kann das Steuerpanel geöffnet werden. Hier lassen sich Presets wählen, Zieltiefe und Zielrate stufenlos regeln sowie zwischen Auto-CPR und Hand-Tracking/Tastatur umschalten.
- **Hand-Tracking / Eingabe:** Im manuellen Modus werden Druckbewegungen der Hände an der Druckzone oder Tastaturdrücke (`C` für Kompression, `V` für Beatmung) direkt als physischer Hub in das QCPR-Protokoll eingespeist.
- **Auto-Modus:** Erzeugt kontinuierlich CPRM-konforme Wellen- und Event-Streams für automatisierte Tests und Vorführungen.

### Anbindung realer Hardware (BLE auf Meta Quest / Android)

Die Architektur trennt Protokoll- und Transportebene über `NaretQcprBackend`:
- Wenn keine reale Puppe verbunden ist, greift der automatische Fallback auf den Simulator.
- Zur Anbindung echter QCPR-Hardware über die Meta Quest 3 wird ein nativer Android-BLE-Wrapper (Godot GDExtension oder Godot Android Plugin, z. B. `GodotBLE`) benötigt:
  1. **Berechtigungen:** `BLUETOOTH_SCAN`, `BLUETOOTH_CONNECT`, `ACCESS_FINE_LOCATION` im Android-Exportpreset aktivieren.
  2. **GATT-Service:** CPRM Command Service `00001001-D746-4092-84E7-DAD34863FE4A` scannen und verbinden.
  3. **Characteristics:** Benachrichtigungen (Notify) auf CPRM Response `00001003-D746-4092-84E7-DAD34863FE4A` und Auth Response `00001033-D746-4092-84E7-DAD34863FE4A` abonnieren; Kommandos an `00001002-...` und `00001032-...` senden.
  4. **Kopplung:** `NaretQcprBleRealBackend` implementiert bereits die vollständige Frame-Verarbeitung und den Auth-Handshake; eintreffende GATT-Pakete werden direkt an `_on_native_characteristic_notified()` weitergeleitet.

## Kalibrierung

1. `assets/textures/markers/aruco_4x4_50_0.png` ausdrucken. Standard: **50 mm schwarzes Quadrat**, der weiße Rand zählt nicht.
2. Marker an der realen Puppe fixieren und im Headset scannen. ID und gemessene Größe im Kalibrierpanel einstellen.
3. „Puppenscan · 1:1-Referenz“ einschalten. Position und Rotation korrigieren, bis der Scan mit der Puppe deckungsgleich ist. Bei korrekter metrischer Vorlage Skalierung 1,0 beibehalten.
4. Offset speichern. Das Schließen stellt die animierte Darstellung wieder her. Der relative Offset wird bei der nächsten Marker-Erkennung erneut angewendet.

Ein verlorener Marker friert die letzte Pose ein und zeigt den Verlust an. Diese Kalibrierung ist kein globaler, zwischen Sessions stabiler OpenXR-Weltanker. Kamera-/Hand-Eye-Kalibrierung und echte Marker-Genauigkeit sind vor Ort zu überprüfen.

## Tests, Messung und Export

```sh
make test       # Domain-, API-, EKG-, Sprach- und Tracking-Suiten
make smoke      # Vollständige Hauptszene: BLS in DE und PL
make benchmark  # Gerenderte Mac-Messung, ausdrücklich kein Quest-Benchmark
```

Die Tests prüfen unter anderem AED-Kontaktsperren, 30:2 und Kompressions-only, zwei Minuten bis zur erneuten AED-Analyse, alle EKG-Rhythmen, Negationen im Sprachparser, API-Cancellation, Queue-Abstände, WAV-Decoding, Marker-Transformationen und einen echten XR-Ray-Klick in ein SubViewport-UI. GitHub Actions prüft den Offline-Desktop-Pfad in einem frischen Checkout; native/hardwareabhängige Funktionen werden separat geprüft.

Session-JSON wird bei Übungsende und über „Export“ nach `user://sessions/` geschrieben. Es enthält Schritte, Zeiten, Fehler und ausdrücklich gekennzeichnete Messdaten, aber keine Transkripte oder API-Schlüssel. Auf macOS liegt `user://` standardmäßig in `~/Library/Application Support/Godot/app_userdata/NaReT · Mannequin XR/`. Auf Android ist es das private `files/`-Verzeichnis der App.

Noch auf der Quest zu validieren: vollständiger Durchlauf mit realer Puppe, Marker-/Hand-Verdeckung, physische Kalibrierung, Mikrofon, tatsächlicher Passthrough sowie stabile 72+ FPS und Draw-Call-Budget. ALS/Medikamententraining ist nicht implementiert; diese Version deckt den BLS-Ablauf ab.

## Lizenz

Eigener Code und prozedurale Trainingsassets: **MIT**. Die beiden Tracking-Submodule: **Unlicense**. OpenXR Vendors hat einen MIT-Wrapper und zusätzliche Plattform-/Loader-Lizenztexte, die mitgeliefert werden. Die Quellen und Modellnachweise bleiben nachvollziehbar in den Submodulen und unter `docs/`. Ein GitHub-Remote ist für dieses neue lokale Projekt noch nicht eingerichtet.
