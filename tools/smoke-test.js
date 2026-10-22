const { chromium } = require('playwright');
const path = require('path');
const URL = 'file://' + path.resolve(__dirname, '../index.html');
// Smoke test: plays the cell stage, uses the editor, finishes the stage, checks for page errors.
// Run: npm i -D playwright && node tools/smoke-test.js (screenshots land in shots/)
(async()=>{
 const b=await chromium.launch();
 const p=await b.newPage({viewport:{width:1280,height:800}});
 const errs=[]; p.on('pageerror',e=>errs.push(e.message)); p.on('console',m=>{if(m.type()==='error')errs.push(m.text())});
 await p.goto(URL); await p.waitForTimeout(800);
 await p.screenshot({path:'shots/1-title.png'});
 await p.click('#pick-meat'); await p.waitForTimeout(500);
 await p.keyboard.down('d'); await p.waitForTimeout(3000); await p.keyboard.up('d');
 await p.mouse.move(900,300); await p.mouse.down(); await p.waitForTimeout(3000); await p.mouse.up();
 await p.screenshot({path:'shots/2-play.png'});
 console.log(await p.evaluate(()=>{const G=__pangaea.G;return {cells:G.cells.length,food:G.food.length,dna:G.dna,prog:G.progress,hp:G.player.hp,mode:G.mode}}));
 // fast-forward: give progress
 await p.evaluate(()=>{const G=__pangaea.G; G.dna=200; G.progress=55; G.level=2;});
 await p.waitForTimeout(1500);
 await p.keyboard.press('e'); await p.waitForTimeout(400);
 await p.click('.part[data-type="spike"]'); 
 const box=await p.locator('#ed-cv').boundingBox();
 await p.mouse.click(box.x+box.width/2+120, box.y+box.height/2);
 await p.click('.part[data-type="eye"]'); await p.mouse.click(box.x+box.width/2+60, box.y+box.height/2-60);
 await p.click('.part[data-type="cilia"]'); await p.mouse.click(box.x+box.width/2, box.y+box.height/2+120);
 await p.mouse.move(box.x+box.width/2, box.y+box.height/2-130);
 await p.waitForTimeout(300);
 await p.screenshot({path:'shots/3-editor.png'});
 await p.click('#ed-done'); await p.waitForTimeout(200);
 console.log(await p.evaluate(()=>JSON.stringify(__pangaea.G.sp.parts.map(x=>x.type))+' mode='+__pangaea.G.mode));
 // simulate a long time headless for stability
 await p.mouse.move(200,600); await p.mouse.down(); await p.waitForTimeout(8000); await p.mouse.up();
 await p.screenshot({path:'shots/4-play2.png'});
 console.log(await p.evaluate(()=>{const G=__pangaea.G;return {cells:G.cells.length,food:G.food.length,dna:G.dna,prog:G.progress,hp:G.player.hp,mode:G.mode,lvl:G.level}}));
 await p.evaluate(()=>{const G=__pangaea.G; G.progress=199; G.level=4;});
 // force-eat
 await p.evaluate(()=>{const G=__pangaea.G,pl=G.player; G.food.push({x:pl.x+Math.cos(pl.heading)*pl.r,y:pl.y+Math.sin(pl.heading)*pl.r,kind:'meat',r:3,val:3,t:0,vx:0,vy:0});});
 await p.waitForTimeout(2000);
 await p.screenshot({path:'shots/5-done.png'});
 console.log('mode',await p.evaluate(()=>__pangaea.G.mode));
 const m=await b.newPage({viewport:{width:390,height:800},isMobile:true,hasTouch:true});
 m.on('pageerror',e=>errs.push(e.message));
 await m.goto(URL); await m.waitForTimeout(500);
 await m.screenshot({path:'shots/6-mobile-title.png'});
 await m.tap('#pick-plant'); await m.waitForTimeout(1500); await m.screenshot({path:'shots/7-mobile-play.png'});
 await m.tap('#evolve-btn'); await m.waitForTimeout(500); await m.screenshot({path:'shots/8-mobile-editor.png'});
 console.log('errors',errs);
 if(errs.length) process.exitCode=1;
 await b.close();
})();
