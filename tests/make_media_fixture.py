import json,secrets,sys
from pathlib import Path
root=Path(sys.argv[1]);name='unityqa'+secrets.token_hex(3)[:5]
fixture={'spawn':[3222,3218,0],'levels':{'6':50,'3':80,'1':60},'items':[{'name':n,'count':c} for n,c in [('airrune',100),('mindrune',100),('earthrune',100),('lawrune',20),('bones',20)]]}
(root/'Saved/skill-fixtures').mkdir(parents=True,exist_ok=True);(root/'Saved/skill-fixtures'/f'{name}.json').write_text(json.dumps(fixture));print(name)
