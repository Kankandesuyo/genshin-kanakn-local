import base64
import json
from pathlib import Path
import urllib.request
import xml.etree.ElementTree as ET
from cryptography.hazmat.primitives.asymmetric import padding, rsa

root = Path(__file__).resolve().parent.parent
credentials = json.loads((root / 'credentials.local.json').read_text(encoding='utf-8-sig'))
xml = ET.fromstring((root / 'runtime/animegamepatch-master/sdk_public_key.xml').read_text())
public_key = rsa.RSAPublicNumbers(
    int.from_bytes(base64.b64decode(xml.findtext('Exponent')), 'big'),
    int.from_bytes(base64.b64decode(xml.findtext('Modulus')), 'big')).public_key()
def encrypted(text):
    return base64.b64encode(public_key.encrypt(text.encode(), padding.PKCS1v15())).decode()
opener = urllib.request.build_opener(urllib.request.ProxyHandler({}))
def login(password):
    body = {'account': encrypted(credentials['playerUsername']), 'password': encrypted(password)}
    request = urllib.request.Request(
        'http://127.0.0.1:8088/hk4e_global/account/ma-passport/api/appLoginByPassword',
        data=json.dumps(body).encode(), headers={'Content-Type': 'application/json'})
    with opener.open(request, timeout=10) as response:
        return json.load(response)['retcode']
good, bad = login(credentials['playerPassword']), login('incorrect-local-client-password')
result = {'encryptedCorrectPasswordRetcode': good, 'encryptedWrongPasswordRetcode': bad}
(root / 'logs/client-sdk-auth-check.json').write_text(json.dumps(result, indent=2))
assert good == 0 and bad != 0, result
print('PASS: encrypted native SDK login succeeds; wrong password is rejected.')
