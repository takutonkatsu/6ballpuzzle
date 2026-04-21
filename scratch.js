const fs = require('fs');
const content = fs.readFileSync('lib/game/puzzle_game.dart', 'utf-8');
const lines = content.split('\n');

let depth = 0;
for (let i = 334; i <= 467; i++) {
  const line = lines[i];
  if (!line) continue;
  let t = line.replace(/\/\/.*$/, ''); // remove comments
  for (let char of t) {
    if (char === '{') depth++;
    if (char === '}') depth--;
  }
  console.log(`${i+1}: ${depth}  ${line.substring(0, 40)}`);
}
