const https = require('https');

function get(url) {
  return new Promise((resolve, reject) => {
    https.get(url, { headers: { 'User-Agent': 'NodeJS' } }, (res) => {
      let data = '';
      res.on('data', chunk => data += chunk);
      res.on('end', () => {
        try {
          resolve(JSON.parse(data));
        } catch (e) {
          reject(e);
        }
      });
    }).on('error', reject);
  });
}

async function main() {
  const data = await get('https://api.github.com/repos/HIT-A/HITA_Android/git/trees/main?recursive=1');
  const tree = data.tree || [];
  const matches = tree.filter(f => {
    const p = f.path.toLowerCase();
    return (p.includes('login') || p.includes('eas') || p.includes('token') || p.includes('auth')) &&
      (p.endsWith('.kt') || p.endsWith('.java') || p.endsWith('.xml'));
  }).map(f => f.path);
  console.log(JSON.stringify(matches, null, 2));
}

main().catch(err => console.error(err));
