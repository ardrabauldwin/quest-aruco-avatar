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

| Figur | Wer | Haltung | Aufgabe im Drehbuch |
| --- | --- | --- | --- |
| **Jan** | Patient, ~55 Jahre, auf dem Boden | Kreislaufstillstand (Kammerflimmern, schockbar) | — |
| **Anna** | Jans Frau | panisch, dicht dran, will helfen, aber weiß nicht wie | Emotionaler Druck: drängt, fragt, reagiert auf gute und schlechte Arbeit, gerät in die Analyse |
| **Marek** | Passant | ruhig, handlungsbereit | Führt Aufträge aus: 112 mit Lautsprecher, AED holen, gibt die Hinweise der Leitstelle weiter, bietet Ablösung an |
| **Leitstelle** | über Mareks Lautsprecher | sachlich | Telefonreanimation: bestätigt, treibt Tempo und Handposition |

**Sprache:** Im Modus *Eigene Sprache* sprechen Anna und Marek die Sprache der übenden Person. Im Modus *Nachbarsprache* sprechen sie die Nachbarsprache (Deutsch ↔ Polnisch). Genau dort liegt der NaReT-Kern: Aufträge und Beruhigung müssen in der Sprache der Umstehenden ankommen.

**Blick und Haltung (gilt immer):** Beide stehen so, dass sie die übende Person und Jan gleichzeitig sehen, und drehen sich mit, wenn die übende Person den Platz wechselt. Sie schauen die übende Person an, wenn sie mit ihr sprechen oder angesprochen werden; während der Kompressionen wechselt der Blick zwischen Brustkorb und Gesicht der übenden Person.

---

## Szenario 1 (Standard): Zusammenbruch auf dem Gehweg

**Ausgangslage:** Grenzübergang Frankfurt (Oder) / Słubice, später Nachmittag. Jan ist auf dem Gehweg zusammengebrochen. Anna kniet nicht, sie steht hilflos daneben. Marek kommt gerade vorbei. Ein öffentlicher AED hängt im Eingang der nahen Apotheke, etwa eine Minute entfernt (in der Übung auf 45 s verkürzt).

**Lernziele:** Algorithmus in der richtigen Reihenfolge; delegieren statt selbst laufen; Unterbrechungen kurz halten; Umstehende während der AED-Analyse sicher auf Abstand bringen.

| # | Auslöser | Anna | Marek / Leitstelle | Erwartet von der übenden Person | Wenn nicht |
| --- | --- | --- | --- | --- | --- |
| 1.1 | Start | `anna_arrive` „Hilfe! Mein Mann ist einfach umgefallen! Bitte helfen Sie ihm!“ Schaut die übende Person an, Hände vor der Brust. | Bleibt stehen, schaut zu. | Sicherheit prüfen, zu Jan gehen. | Nach 8 s ohne Schritt: `anna_urge` „Bitte, tun Sie doch etwas!“ |
| 1.2 | Bewusstsein wird geprüft | `anna_name` „Jan! Jan, hörst du mich?“ | — | Laut ansprechen, an den Schultern rütteln. | — |
| 1.3 | Keine Reaktion bestätigt | — | `marek_offer` „Ich bin hier. Was soll ich tun?“ Kommt näher, schaut die übende Person an. | Laut um Hilfe rufen; Marek einen Auftrag geben. | — |
| 1.4 | „Rufen Sie 112 an, Lautsprecher an!“ (ERC 2025: sofort bei fehlender Reaktion, vor der Atemprüfung) | — | `marek_call` „Ich rufe die 112 an und stelle auf Lautsprecher.“ Handy am Ohr. | 112 sofort veranlassen, nicht erst nach der Atemprüfung. | Wenn nach der fehlenden Reaktion 15 s lang niemand 112 anruft: `marek_prompt_call` „Soll ich den Notruf wählen?“ |
| 1.5 | Atmung wird geprüft, während der Anruf aufgebaut wird | Jan schnappt einmal nach Luft: `anna_agonal` „Er atmet doch noch! Sehen Sie, er atmet!“ | `marek_dispatch` „Die Leitstelle ist dran. Sie fragen, ob er normal atmet.“ | Kopf überstrecken, Kinn anheben, ≤10 s prüfen; Schnappatmung als nicht normal erkennen; der Leitstelle antworten: keine normale Atmung. | Nach 12 s ohne Ergebnis: `anna_breathing` „Atmet er? Sagen Sie doch etwas!“ |
| 1.6 | „Holen Sie den AED!“ | — | `marek_go_aed` „Ich hole den Defibrillator!“ Geht los, verschwindet, kommt nach 45 s mit dem Gerät zurück: `marek_back_aed` „Hier ist der AED! Machen Sie ihn an.“ Stellt ihn neben Jans rechte Schulter. | Einen AED holen lassen und dabei weiterdrücken, nicht selbst gehen. | Wenn nach dem Notruf 20 s lang niemand den AED holen lässt: `marek_prompt_aed` „Soll ich einen Defibrillator suchen?“ |
| 1.7 | Kompressionen, gleichmäßig 100–120/min | Nach 20 guten Kompressionen am Stück: `anna_good` „Ja … Sie machen das gut. Bitte hören Sie nicht auf.“ | — | Rhythmus halten, vollständig entlasten. | — |
| 1.8 | Frequenz < 100/min (3 Hübe in Folge) | — | Leitstelle über Marek: `marek_faster` „Die Leitstelle sagt: schneller drücken!“ | Schneller. | — |
| 1.9 | Frequenz > 125/min (3 Hübe in Folge) | — | `marek_slower` „Etwas langsamer, sagt die Leitstelle.“ | Langsamer. | — |
| 1.10 | Hände nicht auf der Brustmitte | — | `marek_position` „Die Hände in die Mitte der Brust, sagt die Leitstelle.“ | Handballen auf die untere Hälfte des Brustbeins. | — |
| 1.11 | Pause > 10 s während der CPR (nicht beim Beatmen, nicht während AED-Analyse) | `anna_pause` „Bitte nicht aufhören! Machen Sie weiter!“ Schaut die übende Person an. | — | Sofort weiterdrücken. | Wird als Unterbrechung gewertet. |
| 1.12 | AED ist da | — | `marek_take_over` „Ich drücke weiter – kleben Sie die Elektroden!“ Kniet sich gegenüber und drückt weiter (ERC 2025: mit zwei Helfenden läuft die CPR beim Kleben weiter). | AED einschalten, Elektroden rechts unter das Schlüsselbein und links seitlich; Ansagen folgen. | — |
| 1.13 | Analyse läuft | Geht auf Jan zu und will seine Hand nehmen: `anna_touch` „Jan, ich bin da …“ | — | Laut „Abstand! Niemand berührt ihn!“ | Nach 4 s ohne Zuruf berührt Anna Jan: die Analyse bricht ab (Kontaktfehler), der AED fordert neu an. |
| 1.14 | Zuruf „Abstand / nicht berühren“ | `anna_sorry` „Entschuldigung! Ich gehe zurück.“ Tritt zurück. | — | Abstand bestätigen. | — |
| 1.15 | Schock abgegeben | `anna_shock` „Oh Gott! Was war das?“ | — | Sofort weiterdrücken. | Nach 5 s ohne Kompression: `marek_resume` „Das Gerät sagt: sofort weiterdrücken!“ |
| 1.16 | Nach 2 Minuten CPR unterbricht der AED für die nächste Analyse | — | `marek_swap` „Ich kann beim Drücken übernehmen, wenn Sie nicht mehr können.“ | Wechsel beim Drücken anbieten/annehmen (ERC: alle 2 Minuten, während der Analyse). | — |
| 1.17 | Analyse nach 2 min CPR: kein Schock empfohlen, der Kreislauf ist zurück (ob ein Schock wirkt, ist zufällig, spätestens der 3. wirkt; der AED zeigt dann den Puls) | `anna_relief` „Er atmet! Danke! Danke, dass Sie ihm geholfen haben!“ | — | Atmung überwachen, bei normaler Atmung stabile Seitenlage, auf Rettungsdienst warten. | — |
| 1.18 | Übergabe an den Rettungsdienst | — | `marek_ems` „Der Rettungsdienst ist da.“ | Kurze Übergabe: Was ist passiert, seit wann CPR, wie viele Schocks. | — |

---

## Varianten

Jede Variante läuft wie Szenario 1 und ändert nur die genannten Punkte.

### Variante 2: Kein Schock empfohlen
Rhythmus ist Asystolie. Der AED sagt nach der Analyse „Kein Schock empfohlen, sofort weiterdrücken“. Es gibt keinen ROSC; die Übung endet mit der Übergabe (1.18) nach 8 Minuten.
**Lernziel:** Die Wiederbelebung ist auch ohne Schock die Maßnahme, die das Gehirn versorgt. Nicht aufhören, weil das Gerät „nichts tut“.
**Anna:** nach der Analyse `anna_no_shock` „Warum macht das Gerät nichts?“

### Variante 3: Schnappatmung
Bei der Atemprüfung (1.4) macht Jan zwei langsame, schnappende Atemzüge. Anna: `anna_agonal` „Er atmet doch noch! Sehen Sie, er atmet!“
**Lernziel:** Schnappatmung ist keine normale Atmung → sofort 112 und Kompressionen.
**Fehlerbild:** Die übende Person wartet ab oder legt Jan in Seitenlage.

### Variante 4: Nur Anna, nur Nachbarsprache
Marek ist nicht da. Anna versteht nur die Nachbarsprache. Die übende Person muss ihr in der Nachbarsprache sagen, dass sie 112 anrufen, den Lautsprecher einschalten und das Handy neben Jan legen soll. Den AED holt niemand; die Leitstelle schickt ihn mit dem Rettungsdienst.
**Lernziel:** Kernsätze der Nachbarsprache unter Stress: „Rufen Sie 112 an!“ – „Proszę zadzwonić pod 112!“, „Lautsprecher an!“ – „Proszę włączyć głośnik!“

### Variante 5: Panik während der Analyse
Wie 1.13, aber Anna reagiert erst auf den zweiten Zuruf und kommt während der zweiten Analyse erneut näher.
**Lernziel:** Sicherheit vor dem Schock aktiv herstellen, laut, wiederholt, mit Blick auf alle Umstehenden.

### Variante 6: Helferwechsel
Nach 2 Minuten bietet Marek Ablösung an (1.16). Nimmt die übende Person an, kniet Marek sich hin und übernimmt; die übende Person zählt laut mit und übernimmt nach 2 Minuten wieder.
**Lernziel:** Wechsel ohne längere Unterbrechung als ein paar Sekunden, Qualität halten.

---

## Umsetzungsstand

| Teil | Stand |
| --- | --- |
| Szenario 1, Szenen 1.1–1.18 | umgesetzt (`NaretBystanderDirector`) |
| Blickkontakt mit Kopf/Hals, Ausrichtung zur übenden Person | umgesetzt (`NaretRigAnimator`, `NaretBystander`) |
| Marek: Handy am Ohr, AED holen und bringen | umgesetzt; der Weg aus dem Raum endet mit Ausblenden, ein Wegfinden durch die echte Wohnung gibt es nicht |
| Varianten 2–6 | nur beschrieben; die Szenario-Engine kennt bisher `shock_advised` (Variante 2) als Schalter |
| Marek kniet und drückt (Variante 6) | fehlt: braucht eine Kompressions-Animation für ihn |
