"""Loopback-only SMB2 fixture server. Exposes only synthetic test audio."""
from pathlib import Path
from impacket.smbserver import SimpleSMBServer
from impacket.ntlm import compute_lmhash, compute_nthash

server = SimpleSMBServer(listenAddress='127.0.0.1', listenPort=1445)
server.addShare('Music', str(Path(__file__).resolve().parents[1] / 'test' / 'fixtures'), readOnly='yes')
server.setSMB2Support(True)
# Public, disposable test credentials; never use for a real share.
server.addCredential('himusic-test', 0, compute_lmhash('fixture-only'), compute_nthash('fixture-only'))
server.start()
