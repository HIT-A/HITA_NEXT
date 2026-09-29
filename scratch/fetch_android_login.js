const https = require('https');
const fs = require('fs');

function get(url) {
  return new Promise((resolve, reject) => {
    https.get(url, { headers: { 'User-Agent': 'NodeJS' } }, (res) => {
      let data = '';
      res.on('data', chunk => data += chunk);
      res.on('end', () => resolve(data));
    }).on('error', reject);
  });
}

async function fetchFile(repoPath, localPath) {
  const url = `https://raw.githubusercontent.com/HIT-A/HITA_Android/main/${repoPath}`;
  console.log('Fetching', url);
  const content = await get(url);
  fs.writeFileSync(localPath, content);
  console.log('Saved to', localPath, 'length =', content.length);
}

async function main() {
  await fetchFile('app/src/main/java/cn/limpu/hita/ui/eas/login/WebViewLoginActivity.kt', 'scratch/WebViewLoginActivity.kt');
  await fetchFile('app/src/main/java/cn/limpu/hita/ui/eas/login/WebLoginSuccessPolicy.kt', 'scratch/WebLoginSuccessPolicy.kt');
  await fetchFile('app/src/main/java/cn/limpu/hita/ui/eas/login/ShenzhenWebAutoLogin.kt', 'scratch/ShenzhenWebAutoLogin.kt');
  await fetchFile('app/src/main/java/cn/limpu/hita/ui/eas/login/PopUpLoginEAS.kt', 'scratch/PopUpLoginEAS.kt');
}

main().catch(err => console.error(err));
