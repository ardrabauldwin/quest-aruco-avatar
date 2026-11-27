# Drehbuch: BLS-Szenarien mit Umstehenden

Grundlage ist der ERC-Algorithmus „Basismaßnahmen zur Wiederbelebung Erwachsener“ (BLS) nach den [ERC-Leitlinien 2025](https://www.erc.edu/science-research/guidelines/guidelines-2025/guidelines-2025-english). Gegenüber 2021 gilt vor allem: Wer nicht reagiert, bekommt sofort den Notruf 112 (Lautsprecher); die Atmung wird danach geprüft, während der Anruf aufgebaut wird. Schnappatmung, langsames oder hechelndes Atmen zählt als nicht normal. Sind mehrere Helfende da, läuft die Herzdruckmassage weiter, während die Elektroden geklebt werden. Vor dem Einsatz im Kurs prüft die medizinische Leitung jede Szene. Alle polnischen Sätze prüft eine muttersprachliche Person aus dem Projekt, bevor sie eingebacken werden.

Die Sätze der Umstehenden stehen einmal in [`data/bystander_lines.json`](../data/bystander_lines.json). Von dort liest sie die App (`NaretBystanderDirector`), und von dort backen die Audio-Werkzeuge die Offline-Clips. Die Schlüssel in diesem Dokument (`anna_arrive`, …) sind dieselben.

## Was jede Szene trainiert

Die Reihenfolge des Algorithmus bleibt in jedem Szenario gleich. Die Varianten ändern nur, *was die Umgebung tut*:

1. Sicherheit prüfen.
2. Ansprechen und an den Schultern rütteln.
3. Keine Reaktion → laut um Hilfe rufen.
4. Atemwege freimachen (Kopf überstrecken, Kinn anheben), höchstens 10 s auf normale Atmung prüfen: sehen, hören, fühlen. Schnappatmung ist keine normale Atmung.
5. 112 anrufen lassen (Lautsprecher), AED holen lassen.
6. 30 Kompressionen: Mitte der Brust (untere Hälfte des Brustbeins), 5–6 cm, 100–120/min, vollständig entlasten. Dann 2 Beatmungen, wenn ausgebildet und bereit; sonst ununterbrochen drücken.
7. AED einschalten, Elektroden auf die nackte Brust, den Ansagen folgen. Während Analyse und Schock berührt niemand die Person. Danach sofort weiterdrücken.
8. Weitermachen, bis der Rettungsdienst übernimmt, die Person normal atmet oder die Kraft ausgeht. Helfer wechseln sich etwa alle 2 Minuten ab.

## Rollen

| Figur | Wer | Aufgabe in der App (Stand 26.11.2026) |
| --- | --- | --- |
| **Jan** | Patient, ~55 Jahre, auf dem Boden | Kreislaufstillstand (Kammerflimmern, schockbar) |
| **Anna** | Passantin in roter Jacke, kennt Jan nicht | Ruft auf Auftrag 112 an (Lautsprecher); antwortet auf Fragen |
| **Marek** | Passant mit blauem Rucksack | Holt auf Auftrag den AED, bringt ihn und drückt weiter, während die Elektroden geklebt werden |
| **Instruktor** | virtuelle Lehrkraft, außerhalb der Geschichte | Führt bis zum Notruf; danach still; am Ende „Training beendet“ und Debriefing |
| **Leitstelle** | über Annas Lautsprecher | Ab dem Notruf: führt Atemprüfung, Kompressionen, Beatmung, AED und alle Hinweise |
| **Rettungsdienst** | kommt am Ende | Eine Frage zur Übergabe, dann Übernahme |
| **AED** | Gerät | Eigene Ansagen: Elektroden, Analyse, Schock, weiterdrücken |

**Sprache:** Im Modus *Eigene Sprache* sprechen alle die Sprache der übenden Person, im Modus *Nachbarsprache* die Umstehenden die Nachbarsprache (Deutsch ↔ Polnisch). Ein Lauf hat eine Sprache.

---

## Szenario 1 (Standard): Zusammenbruch auf dem Gehweg – aktueller Ablauf

**Ausgangslage:** Grenzübergang Frankfurt (Oder) / Słubice. Jan ist zusammengebrochen; Anna und Marek stehen in der Nähe.

| # | Auslöser | Wer spricht | Satz (DE) | Erwartet von der übenden Person |
| --- | --- | --- | --- | --- |
| 1 | Start | Instruktor | Sicherheitsschritt („Du siehst eine Person, die Hilfe braucht …“) | Umgebung prüfen, „sicher“ melden |
| 2 | Sicherheit gemeldet | Instruktor | Bewusstsein prüfen | Schultern antippen, „reagiert nicht“ melden |
| 3 | Keine Reaktion | Instruktor | „Sprich die Leute direkt an: Bitte jemanden, den Defibrillator zu holen.“ | Marek den AED holen lassen |
| 4 | AED angefordert | Marek | „Ich hole den Defibrillator!“ | — |
| 5 | 3 s danach | Instruktor | „Bitte jetzt jemand anderen, die 112 anzurufen.“ | Anna 112 anrufen lassen |
| 6 | Notruf | Leitstelle | „Notruf 112. Was ist passiert, und wo?“ → übernimmt | Antworten |
| 7 | Atemprüfung | Leitstelle | „Prüf die Atmung: Kopf nach hinten, Kinn hoch, Ohr an den Mund. Atmet die Person normal oder nicht?“ | „Atmet nicht normal“ melden |
| 8 | Kompressionen / Beatmung | Leitstelle | Kompressionen, 2 Beatmungen mit der Maske | 30:2 |
| 9 | Marek ist zurück | Marek / Leitstelle | „Hier ist der AED!“ → „Der AED ist da. Schalte ihn jetzt ein …“ | AED einschalten |
| 10 | AED an | AED / Leitstelle / Marek | Elektroden-Ansage; Hinweise zu den Umrissen; „Ich drücke weiter – kleben Sie die Elektroden!“ | Elektroden kleben |
| 11 | Analyse / Schock | AED / Leitstelle | Analyse, „Schock empfohlen“, Schocktaste; ein Hinweis „Hände weg …“ | Abstand, Schock auslösen, weiterdrücken |
| 12 | Rettungsdienst kommt | Rettungsdienst | „… sagen Sie uns kurz: Reagiert die Person, atmet sie normal, was haben Sie gemacht, und hat der AED einen Schock abgegeben?“ (einmal) | Kurze Übergabe |
| 13 | Übergabe fertig (oder 6 s nach dem letzten Satz) | Rettungsdienst | „Danke. Wir übernehmen jetzt. Treten Sie bitte zurück.“ | Zurücktreten |
| 14 | Ende | Instruktor | „Training beendet …“ + Debriefing (u. a. „Bei der Übergabe fehlte: …“) | — (Sprache wird nicht mehr beantwortet) |

Entfernt am 25./26.11.2026: alle übrigen Sätze von Anna und Marek, Lob und Tempo-Korrekturen während der Kompressionen, Wiederholungen von Leitstelle und Instruktor, die Rückfragen und Ja/Nein-Fragen bei der Übergabe.

---

## Varianten (nur beschrieben, nicht umgesetzt)

### Variante 2: Kein Schock empfohlen
Rhythmus ist Asystolie; der AED sagt „Kein Schock empfohlen, sofort weiterdrücken“. Die Übung endet mit der Übergabe.

### Variante 3: Schnappatmung
Bei der Atemprüfung macht Jan zwei schnappende Atemzüge. Lernziel: Schnappatmung ist keine normale Atmung.

### Variante 4: Nur Anna, nur Nachbarsprache
Marek ist nicht da; Anna versteht nur die Nachbarsprache. Kernsätze: „Rufen Sie 112 an!“ – „Proszę zadzwonić pod 112!“

### Variante 5: Helferwechsel
Nach 2 Minuten übernimmt Marek das Drücken; Wechsel ohne längere Unterbrechung.

---

## Umsetzungsstand

| Teil | Stand |
| --- | --- |
| Szenario 1, Ablauf oben | umgesetzt (`aed_helper_director.gd`, `main.gd`) |
| Neue oder geänderte Sätze | noch ohne Aufnahme (Cloud-Stimme), Liste: Excel „To re-record“ |
| Varianten 2–5 | nur beschrieben |
