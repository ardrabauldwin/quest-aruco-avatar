# BLS-Simulation und fachliche Grenzen

NaReT implementiert das **Erwachsenen-BLS-Szenario nach den ERC-Leitlinien 2025**. Das Programm und die polnischen Fachübersetzungen benötigen vor einem curricularen Einsatz die Prüfung durch qualifizierte Ausbildende. Die Software ist weder klinisch validiert noch ein Medizinprodukt.

## Fachliche Grundlage

Die Primärquelle ist [European Resuscitation Council Guidelines 2025: Adult Basic Life Support, Resuscitation (2025)](https://pubmed.ncbi.nlm.nih.gov/41117574/); Übersicht auf [erc.edu](https://www.erc.edu/science-research/guidelines/guidelines-2025/guidelines-2025-english), Zusammenfassung der Änderungen seit 2021 beim [Resuscitation Council UK](https://www.resus.org.uk/professional-library/2025-resuscitation-guidelines/executive-summary-main-changes-2021-guidelines).

Die umgesetzten Kernpunkte sind: Sicherheit, fehlende Reaktion prüfen, bei fehlender Reaktion sofort Notruf 112 (Lautsprecher) beziehungsweise Hilfsperson beauftragen – neu 2025: vor der Atemprüfung. Während der Anruf aufgebaut wird: Atemwege öffnen und normale Atmung höchstens zehn Sekunden beurteilen. Schnappatmung, langsames oder hechelndes Atmen gilt nicht als normale Atmung; im Zweifel wie Kreislaufstillstand behandeln. AED holen lassen und sofort mit der Herzdruckmassage beginnen. Bei Erwachsenen werden 30 Kompressionen mit zwei Atemspenden kombiniert; wenn Beatmung nicht möglich ist, steht kontinuierliches Drücken zur Verfügung. Die dargestellten Zielwerte sind 100–120 Kompressionen pro Minute, 5–6 cm Drucktiefe, untere Hälfte des Brustbeins und vollständige Entlastung. Ein bereitstehender AED wird ohne vorgeschaltete Mindestzahl von Kompressionen verwendet. Während Analyse und Schock darf niemand die Person berühren. Nach Schock oder Entscheidung gegen einen Schock folgt sofort weitere CPR. Mit mehreren Helfenden läuft die Herzdruckmassage weiter, während die Elektroden geklebt werden; sie ruht nur während Analyse und Schock. Die erneute AED-Analyse folgt nach zwei Minuten. Ob ein Schock das Kammerflimmern beendet, entscheidet die Simulation zufällig (spätestens der dritte wirkt); das zeigt sich erst bei der nächsten Analyse.

## Deterministischer Ablauf

`NaretScenario` besitzt die Zustände `IDLE → INTRO → CHECK_PATIENT → CALL_HELP → CPR ↔ AED → RECOVERY`. Die letzten beiden Übergänge sind ausdrücklich keine physiologische Erfolgsvorhersage.

| Aktion | Bedingung und Ergebnis |
| --- | --- |
| `begin_check` | Bestätigt die Sicherheitsprüfung und öffnet die Patientenprüfung. |
| `check_responsiveness` | Bestätigt die fehlende Reaktion der festgelegten Simulationsperson. |
| `check_breathing` | Erst nach Reaktionsprüfung; fehlende normale Atmung führt zum Notrufschritt. |
| `call_emergency` | Startet den CPR-Abschnitt unmittelbar; die AED-Anforderung blockiert ihn nicht. |
| `request_aed` | Kann bei Notruf, CPR oder AED erfolgen; protokolliert die Delegation. |
| `compression`, `ventilation` | Je ein Simulationsereignis; die Zähler setzen das Verhältnis 30:2 um. |
| `compression_only` | Aktiviert die Alternative ohne Atemspenden. |
| `attach_aed` | Gerät eingeschaltet und Elektroden angelegt; unabhängig von vollendetem CPR-Zyklus verfügbar. |
| `clear_patient`, `analyze_rhythm` | Erste Sicherheitsbestätigung, anschließend simulierte AED-Analyse. |
| `clear_patient`, `shock` | Erneute Sicherheitsbestätigung, Schock nur bei AED-Empfehlung, danach Zustand CPR. |
| `resume_cpr` | Fortsetzung, wenn das AED keinen Schock empfiehlt. |
| `reassess` | Erst nach dem AED-Intervall von 120 simulierten Sekunden verfügbar. |
| `handover` | Ausdrücklich simulierte Übernahme durch den Rettungsdienst, anschließend Nachbesprechung. |
| `simulate_rosc` | Nur mit `{"trainer": true}` und weiterer Kompression nach dem letzten AED-Zyklus. |

Kontakt während des AED-Abschnitts hebt die Freigabe auf. Integrationen übergeben ihn als `patient_contact`, `compression` oder `ventilation`; alle drei führen zur erneuten Sicherheitsprüfung. `get_available_actions()` bietet passende UI-Aktionen, die Zustandsmaschine prüft jedoch jede eingehende Aktion zusätzlich.

Der AED startet mit einer **geskripteten Schockempfehlung**, passend zum VF-Übungsszenario. `shock_advised = false` konfiguriert die nicht schockbare Variante. Das Programm analysiert keine echten EKG-Messdaten. Ein Schock lässt die Simulation stets in CPR zurückkehren. Die Trainingsleitung kann anschließend Lebenszeichen und normale Atmung ausdrücklich simulieren; diese Funktion behauptet keinen automatischen ROSC. Bei Übergabe ohne Lebenszeichen darf die Darstellung ebenfalls keinen Sinusrhythmus als Behandlungserfolg ableiten.

`simulation_speed` ist standardmäßig 1. Eine höhere Einstellung beschleunigt ausschließlich die Übungsuhr und wird im Export dokumentiert. Der AED-Timer misst die Zeit im CPR-Abschnitt; er beweist nicht, dass in diesem Intervall wirksame Kompressionen stattgefunden haben.

## EKG und digitaler Zwilling

`NaretEKG` erzeugt illustrative Kurven für Sinus, pulslose VT, VF, Asystolie und PEA. Ausschließlich der simulierte Sinusrhythmus erzeugt das mechanische `beat`-Signal. Das Signal ist mit dem prozeduralen R-Peak synchron. PEA zeigt elektrische Aktivität ohne mechanischen Puls. Die Darstellung ist kein diagnostisches EKG und kein hämodynamisches Modell. Arzneimittelwirkungen und ALS sind nicht implementiert.

## DE/PL und Nachbesprechung

Alle deterministischen Anweisungen und Aktionsnamen liegen in `NaretLanguage.STRINGS` parallel unter `de` und `pl`. `text(key, language)` wechselt die Sprache ohne Zurücksetzen des Szenarios. Fehlende Schlüssel bleiben sichtbar; eine unbekannte Sprache fällt auf Deutsch zurück.

| Schlüsselbereich | Inhalt für Unterricht und Nachbesprechung |
| --- | --- |
| `state.*` | Trainingsabschnitt |
| `instruction.*` | Konkreter nächster Schritt einschließlich AED-Sicherheitsabfragen |
| `action.*` | Sichtbare Aktionsbezeichnungen |
| `error.*` | Grund eines abgelehnten Schrittes |
| `bystander.*` | Vorbereitete Angehörigendialoge |
| `score.notice` | Hinweis zu Übungsdaten und nicht validierter Bewertung |
| `score.good_sequence` | Akzeptierte Reihenfolge |
| `score.review_sequence` | Zu besprechende Reihenfolge und AED-Sicherheit |

Der Sprachparser erkennt nur Notrufdelegation, AED-Anforderung und Beruhigung. Er bestätigt niemals durch gesprochenen Text eine tatsächlich durchgeführte Kompression, Atemkontrolle oder Schockabgabe.

`NaretScoreTracker` protokolliert akzeptierte/abgelehnte Aktionen, erstmalige Meilensteinzeiten und Fehlergründe. Numerische Drucktiefe und Frequenz fließen nur mit `measurement_verified: true` in die Bereichszähler ein. Diese Kennzeichnung muss eine Integration ausschließlich bei entsprechend geprüften Messdaten setzen; Handpositionen aus XR oder Desktop-Klicks erhalten sie nicht. Es gibt keine klinische Gesamtnote.

`NaretSessionLogger` exportiert versionierte JSON-Dateien unter `user://sessions/`. Die Ereignisse aus der Zustandsmaschine enthalten nur freigegebene strukturierte Felder und keine Transkripte, Audiodaten oder API-Zugangsdaten. Exporte erfolgen lokal, werden nicht automatisch übertragen und müssen für wissenschaftliche Nutzung mit dem jeweiligen Einwilligungs- und Auswertungskonzept abgestimmt werden.

## Prüfen

```sh
godot --headless --xr-mode off --path . --script tests/run_tests.gd
```

Die Tests prüfen den vollständigen Ablauf in beiden Sprachen, 30:2 und reine Kompressionen, früh verfügbare AED-Anwendung, Sicherheitsfreigaben und deren Aufhebung bei Kontakt, schockbare/nicht schockbare Abläufe, die Zwei-Minuten-Grenze, ausdrücklich simulierten ROSC, Rhythmussignale, Übersetzungsvollständigkeit und JSON-Export. Sie ersetzen keine Fachabnahme oder Messvalidierung am realen Phantom.
