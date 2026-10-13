// AI生成
const fs = require('fs');
const luaparse = require('./luaparse.js');
const file = process.argv[2];
const code = fs.readFileSync(file, 'utf8');
try {
  luaparse.parse(code, { luaVersion: '5.1' });
  console.log('SYNTAX_OK: ' + file);
} catch (e) {
  console.log('SYNTAX_ERROR: ' + file);
  console.log(e.message);
  process.exit(1);
}
