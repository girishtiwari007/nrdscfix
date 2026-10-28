from pathlib import Path
import base64,hashlib,re
root=Path(__file__).resolve().parent.parent
template=(root/'tools/index.template.html').read_text(encoding='utf-8-sig')
css='\n'.join((root/name).read_text(encoding='utf-8-sig') for name in ['styles.css','compact.css']).replace('\r\n','\n')
js='\n'.join((root/name).read_text(encoding='utf-8-sig') for name in ['launcher-data.js','app.js']).replace('\r\n','\n')
assert '</style' not in css.lower() and '</script' not in js.lower()
def digest(text):return base64.b64encode(hashlib.sha256(text.encode('utf-8')).digest()).decode('ascii')
style_hash=digest(css);script_hash=digest(js)
policy=f"default-src 'none'; script-src 'self' 'sha256-{script_hash}'; style-src 'self' 'sha256-{style_hash}'; img-src 'self' data:; font-src 'self'; connect-src 'none'; object-src 'none'; base-uri 'none'; form-action 'none'"
html=re.sub(r'<meta http-equiv="Content-Security-Policy" content="[^"]*">',f'<meta http-equiv="Content-Security-Policy" content="{policy}">',template)
html=re.sub(r'<link rel="stylesheet" href="(?:styles|compact)\.css">','',html)
html=re.sub(r'<script defer src="(?:launcher-data|app)\.js"></script>','',html)
html=html.replace('</head>',f'<style id="toolkit-styles">{css}</style>\n</head>')
html=html.replace('</body>',f'<script id="toolkit-behavior">{js}</script>\n</body>')
(root/'index.html').write_text(html,encoding='utf-8',newline='\n')
(root/'toolkit.html').write_text(html,encoding='utf-8',newline='\n')
print('Self-contained page built; exact inline CSS/JS authorized with SHA256 CSP hashes.')
