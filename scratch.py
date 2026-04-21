with open('lib/game/puzzle_game.dart', 'r') as f:
    lines = f.readlines()

depth = 0
for i in range(334, 468):
    line = lines[i]
    t = line.split('//')[0]
    for char in t:
        if char == '{': depth += 1
        if char == '}': depth -= 1
    print(f"{i+1}: {depth}  {line.strip()[:40]}")
