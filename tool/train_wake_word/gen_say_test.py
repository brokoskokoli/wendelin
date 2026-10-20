#!/usr/bin/env python3
"""WP111: Test- und Einlernclips mit den macOS-Systemstimmen (`say`), nur lokale Messung (Apple-SLA, nie ins Repo).

  python gen_say_test.py [--out ~/wendelin-models/kws/wp111/data]
Ausgabe (16 kHz mono, 16 bit):
  pos_wendelin/, pos_hey/  je 9 Stimmen x 5 Rahmen x 3 Tempi, gleiche Saetze/Tempi/Stimmen fuer beide Woerter (Paare)
  conf/                    Verwechsler (Liste aus WP111 + Anleitung `wake/hey`), 9 Stimmen x 2 Tempi
  enroll_hey/              15 Einlern-Clips „Hey Wendelin“ je Stimme (Tempo 130..220) fuer die Vorlagen (Wendelin: data/enroll aus WP106)
Die Stimmen sind unabhaengig von den Piper-Trainingsstimmen (Training: thorsten, kerstin, mls, emo).
"""
import argparse, os, subprocess

VOICES = ["Anna", "Eddy", "Flo", "Grandma", "Grandpa", "Reed", "Rocko", "Sandy", "Shelley"]
FRAMES = ["{w}", "{w}, wie spät ist es?", "{w}, mach das Licht aus", "{w}, wie wird das Wetter morgen?",
          "{w}, stell bitte einen Timer auf zehn Minuten."]
RATES = [150, 175, 205]
CONF = ["Hey Wendel", "Wendeltreppe", "Hey Berlin", "Windel", "wenn die Linie", "Gwendolin", "hey, wenn der Wind weht", "Wendel",
        "Vanille", "Berlin", "Wendelstein", "Mandolin", "Hey Wendy", "Hey Vanille", "Hey Wenzel", "Wenn die Linie ausfällt", "Hey Mandy"]


def say(voice, rate, text, path):
    subprocess.run(["say", "-v", voice, "-r", str(rate), text, "-o", path, "--data-format=LEI16@16000"], check=True)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--out", default=os.path.expanduser("~/wendelin-models/kws/wp111/data"))
    a = ap.parse_args()
    for d in ("pos_wendelin", "pos_hey", "conf", "enroll_hey"):
        os.makedirs(f"{a.out}/{d}", exist_ok=True)
    for v in VOICES:
        for fi, fr in enumerate(FRAMES):
            for r in RATES:
                for d, w in (("pos_wendelin", "Wendelin"), ("pos_hey", "Hey Wendelin")):
                    say(v, r, fr.format(w=w), f"{a.out}/{d}/{v}_f{fi}_r{r}.wav")
        for ci, c in enumerate(CONF):
            for r in (150, 195):
                say(v, r, c, f"{a.out}/conf/{v}_c{ci:02d}_r{r}.wav")
        for i in range(15):
            say(v, 130 + 6 * i, "Hey Wendelin", f"{a.out}/enroll_hey/{v}_{i + 1:02d}.wav")


if __name__ == "__main__":
    main()
