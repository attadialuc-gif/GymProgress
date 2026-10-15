"""Generates GymCore/Sources/GymStore/Resources/exercises.json.

UUIDs are derived with uuid5 from the stable catalogId, so regenerating never changes an id.
Usage: python scripts/gen_catalog.py <output.json>
"""
import json
import sys
import uuid

NS = uuid.UUID("6f1c2a0e-3b7d-4c55-9a8e-1d2f3a4b5c6d")
W, B, D = "weightReps", "bodyweightReps", "duration"

# (catalogId, nombre, medición, equipamiento, loadMode, principales, secundarios[(músculo, factor|None)],
#  incremento, repMín (o seg. mín), repMáx (o seg. máx), descanso)
E = [
    # Pecho
    ("barbell-bench-press", "Press de banca con barra", W, "barbell", "total", ["chest"], [("triceps", None), ("frontDelts", None)], 2.5, 6, 10, 150),
    ("incline-barbell-bench-press", "Press inclinado con barra", W, "barbell", "total", ["chest"], [("frontDelts", None), ("triceps", None)], 2.5, 6, 10, 150),
    ("decline-barbell-bench-press", "Press declinado con barra", W, "barbell", "total", ["chest"], [("triceps", None)], 2.5, 6, 10, 150),
    ("dumbbell-bench-press", "Press de banca con mancuernas", W, "dumbbell", "perSide", ["chest"], [("triceps", None), ("frontDelts", None)], 2, 8, 12, 120),
    ("incline-dumbbell-press", "Press inclinado con mancuernas", W, "dumbbell", "perSide", ["chest"], [("frontDelts", None), ("triceps", None)], 2, 8, 12, 120),
    ("dumbbell-fly", "Aperturas con mancuernas", W, "dumbbell", "perSide", ["chest"], [("frontDelts", 0.3)], 1, 10, 15, 90),
    ("cable-crossover", "Cruce de poleas", W, "cable", "total", ["chest"], [("frontDelts", 0.3)], 2.5, 10, 15, 90),
    ("machine-chest-press", "Press de pecho en máquina", W, "machine", "total", ["chest"], [("triceps", None), ("frontDelts", None)], 5, 8, 12, 120),
    ("pec-deck", "Pec deck (contractor)", W, "machine", "total", ["chest"], [], 5, 10, 15, 90),
    ("smith-bench-press", "Press de banca en Smith", W, "smithMachine", "total", ["chest"], [("triceps", None), ("frontDelts", None)], 2.5, 6, 10, 150),
    ("push-up", "Flexiones de brazos", B, "bodyweight", "total", ["chest"], [("triceps", None), ("frontDelts", None)], 2.5, 8, 20, 90),
    ("chest-dip", "Fondos en paralelas (pecho)", B, "bodyweight", "total", ["chest"], [("triceps", None), ("frontDelts", None)], 2.5, 6, 12, 120),
    # Espalda
    ("pull-up", "Dominadas", B, "bodyweight", "total", ["lats"], [("biceps", None), ("upperBack", None)], 2.5, 5, 10, 150),
    ("chin-up", "Dominadas supinas", B, "bodyweight", "total", ["lats"], [("biceps", None)], 2.5, 5, 10, 150),
    ("assisted-pull-up", "Dominadas asistidas en máquina", B, "machine", "total", ["lats"], [("biceps", None)], 5, 6, 12, 120),
    ("lat-pulldown", "Jalón al pecho", W, "cable", "total", ["lats"], [("biceps", None), ("upperBack", None)], 5, 8, 12, 120),
    ("close-grip-lat-pulldown", "Jalón agarre cerrado", W, "cable", "total", ["lats"], [("biceps", None)], 5, 8, 12, 120),
    ("barbell-row", "Remo con barra", W, "barbell", "total", ["upperBack", "lats"], [("biceps", None), ("rearDelts", None), ("lowerBack", 0.3)], 2.5, 8, 12, 120),
    ("pendlay-row", "Remo Pendlay", W, "barbell", "total", ["upperBack", "lats"], [("biceps", None), ("lowerBack", 0.3)], 2.5, 6, 10, 120),
    ("one-arm-dumbbell-row", "Remo con mancuerna a una mano", W, "dumbbell", "perSide", ["lats", "upperBack"], [("biceps", None), ("rearDelts", None)], 2, 8, 12, 90),
    ("seated-cable-row", "Remo sentado en polea", W, "cable", "total", ["upperBack", "lats"], [("biceps", None), ("rearDelts", None)], 5, 8, 12, 120),
    ("t-bar-row", "Remo en T", W, "barbell", "total", ["upperBack", "lats"], [("biceps", None)], 2.5, 8, 12, 120),
    ("chest-supported-row", "Remo con apoyo en pecho", W, "machine", "total", ["upperBack"], [("lats", None), ("rearDelts", None)], 5, 8, 12, 120),
    ("machine-row", "Remo en máquina", W, "machine", "total", ["upperBack", "lats"], [("biceps", None)], 5, 8, 12, 120),
    ("straight-arm-pulldown", "Pullover en polea", W, "cable", "total", ["lats"], [], 2.5, 10, 15, 90),
    ("deadlift", "Peso muerto convencional", W, "barbell", "total", ["hamstrings", "glutes", "lowerBack"], [("upperBack", None), ("quads", None), ("traps", None), ("forearms", None)], 5, 3, 6, 180),
    ("sumo-deadlift", "Peso muerto sumo", W, "barbell", "total", ["glutes", "quads", "hamstrings"], [("adductors", None), ("lowerBack", None)], 5, 3, 6, 180),
    ("rack-pull", "Rack pull", W, "barbell", "total", ["lowerBack", "upperBack"], [("traps", None), ("glutes", None)], 5, 4, 8, 150),
    ("back-extension", "Hiperextensiones", B, "bodyweight", "total", ["lowerBack"], [("glutes", None), ("hamstrings", None)], 2.5, 10, 15, 90),
    ("barbell-shrug", "Encogimientos con barra", W, "barbell", "total", ["traps"], [("forearms", 0.3)], 5, 10, 15, 90),
    ("dumbbell-shrug", "Encogimientos con mancuernas", W, "dumbbell", "perSide", ["traps"], [("forearms", 0.3)], 2, 10, 15, 90),
    # Hombros
    ("overhead-press", "Press militar con barra", W, "barbell", "total", ["frontDelts"], [("triceps", None), ("sideDelts", None)], 2.5, 5, 8, 150),
    ("dumbbell-shoulder-press", "Press de hombros con mancuernas", W, "dumbbell", "perSide", ["frontDelts"], [("triceps", None), ("sideDelts", None)], 2, 8, 12, 120),
    ("arnold-press", "Press Arnold", W, "dumbbell", "perSide", ["frontDelts"], [("sideDelts", None), ("triceps", None)], 2, 8, 12, 120),
    ("machine-shoulder-press", "Press de hombros en máquina", W, "machine", "total", ["frontDelts"], [("triceps", None)], 5, 8, 12, 120),
    ("dumbbell-lateral-raise", "Elevaciones laterales con mancuernas", W, "dumbbell", "perSide", ["sideDelts"], [], 1, 12, 20, 60),
    ("cable-lateral-raise", "Elevaciones laterales en polea", W, "cable", "perSide", ["sideDelts"], [], 1.25, 12, 20, 60),
    ("machine-lateral-raise", "Elevaciones laterales en máquina", W, "machine", "total", ["sideDelts"], [], 2.5, 12, 20, 60),
    ("dumbbell-front-raise", "Elevaciones frontales", W, "dumbbell", "perSide", ["frontDelts"], [], 1, 10, 15, 60),
    ("rear-delt-fly", "Pájaros con mancuernas", W, "dumbbell", "perSide", ["rearDelts"], [("upperBack", 0.3)], 1, 12, 20, 60),
    ("reverse-pec-deck", "Pec deck inverso", W, "machine", "total", ["rearDelts"], [("upperBack", 0.3)], 2.5, 12, 20, 60),
    ("face-pull", "Face pull", W, "cable", "total", ["rearDelts"], [("upperBack", None), ("traps", 0.3)], 2.5, 12, 20, 60),
    ("upright-row", "Remo al mentón", W, "barbell", "total", ["sideDelts"], [("traps", None)], 2.5, 10, 15, 90),
    # Brazos
    ("barbell-curl", "Curl con barra", W, "barbell", "total", ["biceps"], [("forearms", 0.3)], 2.5, 8, 12, 90),
    ("ez-bar-curl", "Curl con barra Z", W, "ezBar", "total", ["biceps"], [("forearms", 0.3)], 2.5, 8, 12, 90),
    ("dumbbell-curl", "Curl con mancuernas", W, "dumbbell", "perSide", ["biceps"], [("forearms", 0.3)], 1, 8, 15, 75),
    ("hammer-curl", "Curl martillo", W, "dumbbell", "perSide", ["biceps", "forearms"], [], 1, 8, 15, 75),
    ("incline-dumbbell-curl", "Curl inclinado con mancuernas", W, "dumbbell", "perSide", ["biceps"], [], 1, 8, 15, 75),
    ("preacher-curl", "Curl predicador", W, "ezBar", "total", ["biceps"], [], 2.5, 8, 12, 75),
    ("cable-curl", "Curl en polea", W, "cable", "total", ["biceps"], [("forearms", 0.3)], 2.5, 10, 15, 75),
    ("concentration-curl", "Curl concentrado", W, "dumbbell", "perSide", ["biceps"], [], 1, 10, 15, 60),
    ("cable-triceps-pushdown", "Extensión de tríceps en polea", W, "cable", "total", ["triceps"], [], 2.5, 10, 15, 75),
    ("overhead-cable-triceps-extension", "Extensión de tríceps sobre la cabeza en polea", W, "cable", "total", ["triceps"], [], 2.5, 10, 15, 75),
    ("skull-crusher", "Press francés", W, "ezBar", "total", ["triceps"], [], 2.5, 8, 12, 90),
    ("dumbbell-overhead-triceps-extension", "Extensión de tríceps con mancuerna", W, "dumbbell", "total", ["triceps"], [], 2, 10, 15, 75),
    ("close-grip-bench-press", "Press de banca agarre cerrado", W, "barbell", "total", ["triceps"], [("chest", None), ("frontDelts", None)], 2.5, 6, 10, 120),
    ("triceps-dip", "Fondos en paralelas (tríceps)", B, "bodyweight", "total", ["triceps"], [("chest", None), ("frontDelts", None)], 2.5, 6, 12, 120),
    ("bench-dip", "Fondos en banco", B, "bodyweight", "total", ["triceps"], [("chest", 0.3)], 2.5, 10, 20, 75),
    ("wrist-curl", "Curl de muñeca", W, "barbell", "total", ["forearms"], [], 1, 12, 20, 60),
    ("farmers-walk", "Paseo del granjero", D, "dumbbell", "perSide", ["forearms", "traps"], [("abs", 0.3)], 2, 30, 60, 90),
    # Piernas
    ("barbell-back-squat", "Sentadilla con barra", W, "barbell", "total", ["quads", "glutes"], [("adductors", None), ("lowerBack", 0.3)], 2.5, 5, 8, 180),
    ("front-squat", "Sentadilla frontal", W, "barbell", "total", ["quads"], [("glutes", None), ("upperBack", 0.3)], 2.5, 5, 8, 180),
    ("goblet-squat", "Sentadilla goblet", W, "dumbbell", "total", ["quads", "glutes"], [("adductors", None)], 2, 8, 12, 120),
    ("smith-squat", "Sentadilla en Smith", W, "smithMachine", "total", ["quads", "glutes"], [], 2.5, 8, 12, 150),
    ("hack-squat", "Sentadilla hack", W, "machine", "total", ["quads"], [("glutes", None)], 5, 8, 12, 150),
    ("leg-press", "Prensa de piernas", W, "machine", "total", ["quads", "glutes"], [("adductors", None)], 5, 10, 15, 150),
    ("bulgarian-split-squat", "Sentadilla búlgara", W, "dumbbell", "perSide", ["quads", "glutes"], [("adductors", None)], 2, 8, 12, 120),
    ("walking-lunge", "Estocadas caminando", W, "dumbbell", "perSide", ["quads", "glutes"], [("adductors", None)], 2, 8, 12, 120),
    ("reverse-lunge", "Estocadas hacia atrás", W, "dumbbell", "perSide", ["quads", "glutes"], [], 2, 8, 12, 120),
    ("step-up", "Subidas al cajón", W, "dumbbell", "perSide", ["quads", "glutes"], [], 2, 8, 12, 90),
    ("leg-extension", "Extensión de cuádriceps", W, "machine", "total", ["quads"], [], 5, 10, 15, 75),
    ("romanian-deadlift", "Peso muerto rumano", W, "barbell", "total", ["hamstrings", "glutes"], [("lowerBack", None)], 2.5, 8, 12, 150),
    ("dumbbell-romanian-deadlift", "Peso muerto rumano con mancuernas", W, "dumbbell", "perSide", ["hamstrings", "glutes"], [("lowerBack", None)], 2, 8, 12, 120),
    ("stiff-leg-deadlift", "Peso muerto piernas rígidas", W, "barbell", "total", ["hamstrings"], [("glutes", None), ("lowerBack", None)], 2.5, 8, 12, 150),
    ("lying-leg-curl", "Curl femoral acostado", W, "machine", "total", ["hamstrings"], [], 2.5, 10, 15, 75),
    ("seated-leg-curl", "Curl femoral sentado", W, "machine", "total", ["hamstrings"], [], 2.5, 10, 15, 75),
    ("nordic-curl", "Curl nórdico", B, "bodyweight", "total", ["hamstrings"], [], 2.5, 4, 10, 120),
    ("good-morning", "Buenos días", W, "barbell", "total", ["hamstrings", "lowerBack"], [("glutes", None)], 2.5, 8, 12, 120),
    ("hip-thrust", "Hip thrust con barra", W, "barbell", "total", ["glutes"], [("hamstrings", None)], 5, 8, 12, 120),
    ("glute-bridge", "Puente de glúteos", W, "barbell", "total", ["glutes"], [("hamstrings", 0.3)], 5, 10, 15, 90),
    ("cable-kickback", "Patada de glúteo en polea", W, "cable", "perSide", ["glutes"], [], 1.25, 10, 15, 60),
    ("hip-abduction-machine", "Abducción de cadera en máquina", W, "machine", "total", ["abductors"], [("glutes", None)], 5, 12, 20, 60),
    ("hip-adduction-machine", "Aducción de cadera en máquina", W, "machine", "total", ["adductors"], [], 5, 12, 20, 60),
    ("standing-calf-raise", "Elevación de talones de pie", W, "machine", "total", ["calves"], [], 5, 10, 15, 60),
    ("seated-calf-raise", "Elevación de talones sentado", W, "machine", "total", ["calves"], [], 5, 12, 20, 60),
    ("leg-press-calf-raise", "Gemelos en prensa", W, "machine", "total", ["calves"], [], 5, 12, 20, 60),
    # Core
    ("plank", "Plancha", D, "bodyweight", "total", ["abs"], [("obliques", None)], 2.5, 30, 60, 60),
    ("side-plank", "Plancha lateral", D, "bodyweight", "perSide", ["obliques"], [("abs", None)], 2.5, 20, 45, 60),
    ("crunch", "Abdominales crunch", B, "bodyweight", "total", ["abs"], [], 2.5, 12, 25, 60),
    ("cable-crunch", "Crunch en polea", W, "cable", "total", ["abs"], [], 2.5, 10, 15, 60),
    ("hanging-leg-raise", "Elevación de piernas colgado", B, "bodyweight", "total", ["abs"], [("obliques", None)], 2.5, 8, 15, 75),
    ("ab-wheel-rollout", "Rueda abdominal", B, "bodyweight", "total", ["abs"], [("lats", 0.3)], 2.5, 8, 15, 75),
    ("russian-twist", "Giros rusos", W, "other", "total", ["obliques"], [("abs", None)], 2, 12, 20, 60),
    ("pallof-press", "Press Pallof", W, "cable", "perSide", ["obliques"], [("abs", None)], 1.25, 10, 15, 60),
    ("dead-bug", "Dead bug", B, "bodyweight", "total", ["abs"], [], 2.5, 8, 15, 60),
    # Otros
    ("kettlebell-swing", "Swing con kettlebell", W, "kettlebell", "total", ["glutes", "hamstrings"], [("lowerBack", None)], 4, 12, 20, 90),
    ("power-clean", "Cargada de potencia", W, "barbell", "total", ["glutes", "quads", "traps"], [("hamstrings", None), ("upperBack", None)], 2.5, 2, 5, 180),
    ("landmine-press", "Press landmine", W, "barbell", "perSide", ["frontDelts", "chest"], [("triceps", None)], 2.5, 8, 12, 90),
]


def main(path):
    seen = set()
    out = []
    for (cid, name, meas, eq, lm, prim, sec, inc, rmin, rmax, rest) in E:
        assert cid not in seen, cid
        seen.add(cid)
        out.append({
            "uuid": str(uuid.uuid5(NS, cid)).upper(),
            "catalogId": cid,
            "name": name,
            "measurement": meas,
            "equipment": eq,
            "loadMode": lm,
            "primary": prim,
            "secondary": [({"muscle": m, "factor": f} if f is not None else {"muscle": m}) for m, f in sec],
            "increment": inc,
            "repMin": rmin,
            "repMax": rmax,
            "restSeconds": rest,
        })
    with open(path, "w", encoding="utf-8", newline="\n") as fh:
        json.dump({"version": 1, "exercises": out}, fh, ensure_ascii=False, indent=1)
        fh.write("\n")
    print(len(out))


if __name__ == "__main__":
    main(sys.argv[1])
