import sys

def check_brackets(filename):
    with open(filename, 'r') as f:
        lines = f.readlines()
    
    stack = []
    for i, line in enumerate(lines):
        line_num = i + 1
        for char in line:
            if char == '{':
                stack.append(('{', line_num))
            elif char == '}':
                if not stack:
                    print(f"Extra '}}' at line {line_num}")
                else:
                    stack.pop()
    
    if stack:
        for char, line in stack:
            print(f"Unclosed '{char}' from line {line}")

print("Checking PuzzleGame:")
check_brackets('lib/game/puzzle_game.dart')
print("\nChecking GameScreen:")
check_brackets('lib/ui/game_screen.dart')
