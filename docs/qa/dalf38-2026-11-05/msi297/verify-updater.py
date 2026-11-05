import base64,hashlib,json,sys
from pathlib import Path
from cryptography.hazmat.primitives.asymmetric.ed25519 import Ed25519PublicKey
from cryptography.exceptions import InvalidSignature

def verify(data,signature,public):
 pub=base64.b64decode(public,validate=True).decode().splitlines()
 key=base64.b64decode(pub[1],validate=True)
 if len(key)!=42 or key[:2]!=b'Ed':raise ValueError('Invalid public key')
 lines=base64.b64decode(signature.strip(),validate=True).decode().splitlines()
 if len(lines)!=4 or not lines[2].startswith('trusted comment: '):raise ValueError('Invalid signature envelope')
 sig=base64.b64decode(lines[1],validate=True)
 if len(sig)!=74 or sig[:2] not in (b'Ed',b'ED') or sig[2:10]!=key[2:10]:raise ValueError('Invalid signature identity')
 pk=Ed25519PublicKey.from_public_bytes(key[10:])
 payload=hashlib.blake2b(data,digest_size=64).digest() if sig[:2]==b'ED' else data
 pk.verify(sig[10:],payload)
 comment=lines[2][len('trusted comment: '):]
 pk.verify(base64.b64decode(lines[3],validate=True),sig[10:]+comment.encode())
 return comment

if __name__=='__main__':
 msi,config=map(Path,sys.argv[1:3]);data=msi.read_bytes();signature=Path(str(msi)+'.sig').read_text()
 pub=json.loads(config.read_text())['plugins']['updater']['pubkey']
 comment=verify(data,signature,pub)
 mutated=bytearray(data);mutated[len(mutated)//2]^=1
 try:verify(mutated,signature,pub)
 except InvalidSignature:pass
 else:raise AssertionError('Tampered payload accepted')
 env=base64.b64decode(signature.strip()).decode().splitlines();env[2]+=' tampered'
 try:verify(data,base64.b64encode('\n'.join(env).encode()),pub)
 except InvalidSignature:pass
 else:raise AssertionError('Tampered trusted comment accepted')
 print(json.dumps(dict(sha256=hashlib.sha256(data).hexdigest(),length=len(data),signatureValid=True,trustedCommentValid=True,trustedComment=comment,tamperedPayloadRejected=True,tamperedCommentRejected=True),indent=2))
