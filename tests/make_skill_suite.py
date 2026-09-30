#!/usr/bin/env python3
"""Generate one-shot, disposable QA fixtures and a native Unity action manifest.
Fixture items/levels are prerequisites, never counted as gameplay successes.
No existing character is edited. Run with SCAPE_TEST_FIXTURE_DIR enabled server-side.
"""
import argparse,json,secrets
from pathlib import Path
p=argparse.ArgumentParser();p.add_argument('output',type=Path);p.add_argument('--only',default='');p.add_argument('--fixtures',type=Path);a=p.parse_args()
a.output.mkdir(parents=True,exist_ok=True);fixtures=a.fixtures or a.output/'fixtures';fixtures.mkdir(exist_ok=True)
cases=[]
def step(label,kind,**kw):
 result=dict(label=label,kind=kind,skill=-1,style=-1,level=-1,expectedItemCount=-1,mainRoot=-1,timeout=60 if 'skill' in kw else 35)
 result.update(kw);return result

def add(name,steps,items=(),spawn=(3222,3218,0),levels=None,currentLevels=None):
 if a.only and name not in a.only.split(','):return
 username='unityqa'+secrets.token_hex(3)[:5]
 fixture=dict(spawn=spawn,items=[dict(name=n,count=c) for n,c in items],levels=levels or {},currentLevels=currentLevels or {})
 (fixtures/(username+'.json')).write_text(json.dumps(fixture,indent=2))
 cases.append(dict(name=name,username=username,steps=steps,setup=fixture))
for name,skill,button in [('attack',0,2282),('strength',2,2285),('defence',1,2283),('hitpoints',3,2282)]:
 add(name,[step('Equip bronze sword','held',item=1277,count=2,equippedId=1277),step('Choose combat style','button',button=button,style={2282:0,2285:1,2283:3}[button]),step('Attack a man; earn skill XP','target',target='npc',name='Man',operation='Attack',skill=skill)], [('bronze_sword',1)],levels={'0':30,'1':60,'2':10,'3':80})
add('ranged',[step('Equip shortbow','held',item=841,count=2,equippedId=841),step('Equip arrows','held',item=882,count=2,equippedId=882),step('Accurate ranged style','button',button=1772,style=0),step('Shoot a man; earn ranged XP','target',target='npc',name='Man',operation='Attack',skill=4)], [('shortbow',1),('bronze_arrow',100)],levels={'4':30,'1':60,'3':80})
add('magic',[step('Cast Wind Strike','cast',target='npc',name='Goblin',operation='Attack',button=1152,skill=6,product=558,delta=-1)], [('airrune',100),('mindrune',100)],spawn=(3255,3227,0),levels={'1':60,'3':80})
add('prayer',[step('Bury bones','held',item=526,count=1,skill=5,product=526,delta=-1)], [('bones',1)])
add('woodcutting',[step('Chop tree into logs','target',target='loc',name='Tree',operation='Chop down',skill=8,product=1511,delta=1)], [('bronze_axe',1)])
add('firemaking',[step('Light logs with tinderbox','use',item=1511,useItem=590,skill=11,product=1511,delta=-1)], [('logs',1),('tinderbox',1)],spawn=(3231,3219,0))
add('fishing',[step('Net a shrimp','target',target='npc',name='Fishing spot',operation='Net',skill=10,product=317,delta=1)], [('net',1)],spawn=(3266,3149,0),levels={'1':60,'3':80})
add('mining',[step('Mine a rock','target',target='loc',name='Rocks',targetId=2090,operation='Mine',skill=14)], [('bronze_pickaxe',1)],spawn=(3285,3365,0))
add('cooking',[step('Cook raw shrimp on range','useTarget',target='loc',name='Range',item=317,skill=7,product=315,delta=1)], [('raw_shrimp',1)],spawn=(3231,3197,0),levels={'7':50})
add('smithing',[step('Smelt copper and tin into bronze','useTarget',target='loc',name='Furnace',item=436,skill=13,product=2349,delta=1)], [('copper_ore',1),('tin_ore',1)],spawn=(3227,3255,0))
add('crafting',[step('Cut a sapphire','use',item=1623,useItem=1755,skill=12,product=1607,delta=1)], [('chisel',1),('uncut_sapphire',1)],levels={'12':20})
add('fletching',[step('Feather fifteen arrow shafts','use',item=52,useItem=314,skill=9,product=53,delta=15)], [('arrow_shaft',15),('feather',15)])
add('herblore',[step('Identify guam','held',item=199,count=1,skill=15,product=249,delta=1),step('Add guam to water','use',item=227,useItem=249,product=91,delta=1),step('Brew attack potion','use',item=91,useItem=221,skill=15)], [('unidentified_guam',1),('vial_water',1),('eye_of_newt',1)],levels={'15':3})
add('agility',[step('Cross gnome log balance','target',target='loc',name='Log balance',operation='Walk-across',skill=16)],spawn=(2474,3437,0))
add('thieving',[step('Pickpocket a man','target',target='npc',name='Man',operation='Pickpocket',skill=17,product=995,delta=3,retrySeconds=8)],levels={'17':70,'3':80})
add('runecraft',[step('Bind essence at air altar','target',target='loc',name='Altar',operation='Craft-rune',skill=20,product=556,delta=3)], [('blankrune',3)],spawn=(2843,4830,0))
add('crafting_level_rejection',[step('Reject sapphire below required level','use',item=1623,useItem=1755,skill=12,expectNoXp=True,message='Crafting level')],[('chisel',1),('uncut_sapphire',1)])
add('mining_tool_rejection',[step('Reject mining without pickaxe','target',target='loc',name='Rocks',targetId=2090,operation='Mine',skill=14,expectNoXp=True,message='pickaxe')],spawn=(3285,3365,0))
add('banking',[step('Open bank booth','target',target='loc',name='Bank booth',operation='Use-quickly',expectMain=True),step('Deposit coins','invbutton',item=995,operation='Deposit 1',product=995,delta=-1),step('Withdraw X','invbutton',item=995,operation='Withdraw X',expectCount=True),step('Confirm quantity','count',count=1,product=995,delta=1)],[('coins',10)],spawn=(3093,3244,0))

# Multi-step gameplay and UI coverage beyond each skill's baseline.
add('crafting_leather',[step('Open leather crafting menu','use',item=1741,useItem=1733,expectMain=True),step('Make leather gloves','button',button=8638,skill=12,product=1059,delta=1)],[('needle',1),('thread',5),('leather',1)])
add('fletching_logs',[step('Open log fletching choices','use',item=1511,useItem=946,expectDialog=True),step('Choose arrow shafts','button',button=8889,skill=9,product=52,delta=15)],[('logs',1),('knife',1)])
add('fletching_bow',[step('String a shortbow','use',item=50,useItem=1777,skill=9,product=841,delta=1)],[('unstrung_shortbow',1),('bow_string',1)],levels={'9':5})
add('smithing_anvil',[step('Open bronze smithing interface','useTarget',target='loc',name='Anvil',item=2349,expectMain=True),step('Smith bronze dagger','invbutton',item=1205,operation='Make',skill=13,product=1205,delta=1)],[('bronze_bar',1),('hammer',1)],spawn=(3187,3425,0))
add('smelting_quantity',[step('Open furnace recipe menu','target',target='loc',name='Furnace',operation='Smelt',expectDialog=True),step('Choose bronze Smelt X','button',button=2414,expectCount=True),step('Smelt two bars','count',count=2,skill=13,product=2349,delta=2)],[('copper_ore',2),('tin_ore',2)],spawn=(3227,3255,0))
add('agility_lap',[
 step('Log balance','target',target='loc',targetId=2295,operation='Walk-across',skill=16),
 step('First net to floor one','target',target='loc',targetId=2285,operation='Climb-over',skill=16,level=1,requireLowerFloor=True),
 step('Tree to floor two','target',target='loc',targetId=2313,operation='Climb',skill=16,level=2,requireLowerFloor=True),
 step('Cross rope','target',target='loc',targetId=2312,operation='Walk-on',skill=16),
 step('Climb down tree','target',target='loc',targetId=2314,operation='Climb-down',skill=16,level=0),
 step('Final net','target',target='loc',targetId=2286,operation='Climb-over',skill=16),
 step('Pipe and lap reward','target',target='loc',name='Obstacle pipe',operation='Squeeze-through',skill=16),
],spawn=(2474,3437,0))
add('runecraft_travel',[
 step('Enter ruins with air talisman','useTarget',target='loc',name='Mysterious ruins',item=1438,minX=2800,maxX=2900,minZ=4800,maxZ=4880),
 step('Craft air runes','target',target='loc',name='Altar',operation='Craft-rune',skill=20,product=556,delta=3),
 step('Exit through portal','target',target='loc',name='Portal',operation='Use',minX=2950,maxX=3010,minZ=3270,maxZ=3320),
],[('air_talisman',1),('blankrune',3)],spawn=(2983,3290,0))
prayers=[]
for button in range(5609,5624):
 prayers += [step(f'Activate prayer {button-5609}','button',button=button,checkButton=button,activeValue=True),step(f'Deactivate prayer {button-5609}','button',button=button,checkButton=button,activeValue=False)]
add('prayer_toggles',prayers,levels={'5':45})
add('shop',[
 step('Trade with shop keeper','target',target='npc',name='Shop keeper',operation='Trade',expectMain=True),
 step('Buy a jug','invbutton',item=1935,operation='Buy 1',product=1935,delta=1),
 step('Sell bronze sword','invbutton',item=1277,operation='Sell 1',product=1277,delta=-1),
],[('coins',100),('bronze_sword',1)],spawn=(3214,3241,0))
add('cooks_assistant',[
 step('Talk to Cook','target',target='npc',name='Cook',operation='Talk-to',expectDialog=True),
 step('Accept ingredient quest','dialogue',choices="What's wrong?|Yes, I'll help you.",expectChatClosed=True,timeout=100),
 step('Return with ingredients','target',target='npc',name='Cook',operation='Talk-to',expectDialog=True),
 step('Hand over ingredients and complete quest','dialogue',skill=7,product=1944,delta=-1,expectMain=True,timeout=100),
 step('Close reward panel','close'),
 step('Read completed quest journal','button',button=7333,expectMain=True,message='QUEST COMPLETE'),
 step('Close journal','close'),
 step('Cook on newly unlocked range','useTarget',target='loc',name='Cooking range',item=317,skill=7,product=315,delta=1),
],[('bucket_milk',1),('pot_flour',1),('egg',1),('raw_shrimp',1)],spawn=(3208,3214,0),levels={'7':50})
add('mining_full_inventory',[step('Reject mining with full inventory','target',target='loc',targetId=2090,operation='Mine',skill=14,expectNoXp=True,message='too full')],[('bronze_pickaxe',1),('logs',27)],spawn=(3285,3365,0))
add('magic_missing_runes',[step('Reject Wind Strike without runes','cast',target='npc',name='Man',operation='Attack',button=1152,skill=6,expectNoXp=True,message='runes')],levels={'3':80})
add('food_healing',[step('Eat shrimp and restore hitpoints','held',item=315,count=1,product=315,delta=-1,healthGain=3)],[('shrimp',1)],levels={'3':10},currentLevels={'3':5})
add('food_healing_cap',[step('Food healing stops at maximum HP','held',item=315,count=1,product=315,delta=-1,healthGain=1)],[('shrimp',1)],levels={'3':10},currentLevels={'3':9})
(a.output/'suite.json').write_text(json.dumps(dict(cases=cases),indent=2))
print(f'{len(cases)} disposable native Unity cases generated in {a.output}')
