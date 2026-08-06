/* 《君子之盾》 3D — Three.js 渲染层 + 已验证的玩法逻辑 */
import * as THREE from 'three';
import { GLTFLoader } from 'three/examples/jsm/loaders/GLTFLoader.js';
import { clone as skClone } from 'three/examples/jsm/utils/SkeletonUtils.js';
import { MODELS_B64 } from './assets/models.js';

/* ================= 基础 ================= */
const $=s=>document.querySelector(s);
const clamp=(v,a,b)=>Math.max(a,Math.min(b,v));
const dist=(a,b,c,d)=>Math.hypot(a-c,b-d);
const lerpK=(dt,speed)=>1-Math.exp(-dt*speed);

/* ================= 音频引擎（全程序合成，无采样文件） ================= */
let AC=null, muted=false, master=null, busSfx=null, busMus=null, busAmb=null;
function ac(){
  if(!AC){
    AC=new (window.AudioContext||window.webkitAudioContext)();
    master=AC.createGain(); master.gain.value=1; master.connect(AC.destination);
    busSfx=AC.createGain(); busSfx.gain.value=.9;  busSfx.connect(master);
    busMus=AC.createGain(); busMus.gain.value=.6;  busMus.connect(master);
    busAmb=AC.createGain(); busAmb.gain.value=.85; busAmb.connect(master);
  }
  return AC;
}
function tone(f,dur,type='square',vol=0.05,slide=0,at=0){
  if(muted||!AC) return;
  try{
    const t0=AC.currentTime+at;
    const o=AC.createOscillator(), g=AC.createGain();
    o.type=type; o.frequency.setValueAtTime(f,t0);
    if(slide) o.frequency.linearRampToValueAtTime(Math.max(30,f+slide),t0+dur);
    g.gain.setValueAtTime(0,t0);
    g.gain.linearRampToValueAtTime(vol,t0+.006);
    g.gain.exponentialRampToValueAtTime(0.0001,t0+dur);
    o.connect(g); g.connect(busSfx); o.start(t0); o.stop(t0+dur+.05);
  }catch(e){}
}
let _noise=null;
function noiseBuffer(){
  if(!_noise){
    const sr=AC.sampleRate;
    _noise=AC.createBuffer(1,sr*2,sr);
    const d=_noise.getChannelData(0);
    for(let i=0;i<d.length;i++) d[i]=Math.random()*2-1;
  }
  return _noise;
}
function noiseHit({dur=.2,freq=1000,q=1,type='bandpass',vol=.1,at=0,slide=0,attack=.006,bus}={}){
  if(muted||!AC) return;
  try{
    const t0=AC.currentTime+at;
    const s=AC.createBufferSource(); s.buffer=noiseBuffer(); s.loop=true;
    const f=AC.createBiquadFilter(); f.type=type; f.Q.value=q;
    f.frequency.setValueAtTime(freq,t0);
    if(slide) f.frequency.linearRampToValueAtTime(Math.max(50,freq+slide),t0+dur);
    const g=AC.createGain();
    g.gain.setValueAtTime(0,t0);
    g.gain.linearRampToValueAtTime(vol,t0+attack);
    g.gain.exponentialRampToValueAtTime(.0001,t0+dur);
    s.connect(f); f.connect(g); g.connect(bus||busSfx);
    s.start(t0); s.stop(t0+dur+.1);
  }catch(e){}
}
function metal(fs,dur,vol,at=0){ fs.forEach((f,i)=>tone(f,dur*(1-i*.1),'square',vol*Math.pow(.62,i),0,at)); }
/* Karplus-Strong 拨弦（琉特琴） */
const _pluck={};
function pluckBuf(freq){
  const key=Math.round(freq);
  if(_pluck[key]) return _pluck[key];
  const sr=AC.sampleRate, N=Math.max(8,Math.round(sr/freq)), len=(sr*1.1)|0;
  const buf=AC.createBuffer(1,len,sr), d=buf.getChannelData(0);
  const ring=new Float32Array(N);
  for(let i=0;i<N;i++) ring[i]=Math.random()*2-1;
  let idx=0;
  for(let i=0;i<len;i++){
    const cur=ring[idx], nxt=ring[(idx+1)%N];
    d[i]=cur; ring[idx]=.996*.5*(cur+nxt); idx=(idx+1)%N;
  }
  _pluck[key]=buf; return buf;
}
function pluck(freq,vol=.1,at=0){
  if(muted||!AC) return;
  try{
    const t0=AC.currentTime+at;
    const s=AC.createBufferSource(); s.buffer=pluckBuf(freq);
    const g=AC.createGain(); g.gain.value=vol;
    s.connect(g); g.connect(busMus); s.start(t0);
  }catch(e){}
}
function crowdSwell(v=1){
  if(duel&&duel.foeId==='brigand') return;   /* 荒林无观众 */
  noiseHit({dur:1.5,freq:640,q:.7,vol:.09*v,attack:.28,bus:busAmb});
}
function hornNote(f,dur,at,vol=.05){
  tone(f,dur,'sawtooth',vol,0,at); tone(f*1.005,dur,'sawtooth',vol*.5,0,at);
  tone(f/2,dur,'triangle',vol*.6,0,at);
}
const sfx={
  clang(){ metal([2470,3160,4680],.17,.05); noiseHit({dur:.07,freq:6500,type:'highpass',vol:.05}); tone(170,.1,'triangle',.05,-50); },
  hit(){ noiseHit({dur:.16,freq:320,type:'lowpass',vol:.15}); tone(105,.2,'sine',.11,-45); metal([2900,4150],.05,.018,.015); crowdSwell(.35); },
  swing(){ noiseHit({dur:.14,freq:650,q:2.2,vol:.05,slide:950}); },
  shove(){ noiseHit({dur:.18,freq:210,type:'lowpass',vol:.15}); metal([2600,3900],.06,.02,.01); },
  horn(){ hornNote(392,.4,0); hornNote(523.25,.7,.28); },
  fanfare(){ hornNote(392,.28,0); hornNote(523.25,.28,.24); hornNote(659.25,.9,.48,.06); crowdSwell(1.2); },
  coin(){ tone(1320,.1,'sine',.04); tone(1760,.16,'sine',.035,0,.07); },
  yield_(){ tone(660,.35,'sine',.045,-170); this.fanfare(); },
  crack(){ noiseHit({dur:.26,freq:1600,q:.6,vol:.17,slide:-1000}); tone(62,.3,'sine',.13,-22);
    for(let i=0;i<3;i++) noiseHit({dur:.05,freq:3200+i*900,vol:.04,at:.03+i*.045});
    crowdSwell(.8); },
  hoof(v=1){ noiseHit({dur:.06,freq:260,type:'lowpass',vol:.08*v}); tone(72,.05,'sine',.055*v,-18); },
  brace(q){ tone(210,.08,'square',.05); metal([3300],.05,.02,.02);
    if(q>.85) tone(1568,.14,'sine',.04,0,.05); },
  drum(v=1){ tone(60,.26,'sine',.13*v,-16); noiseHit({dur:.07,freq:160,type:'lowpass',vol:.05*v}); },
  cheer(v=1){ crowdSwell(1.4*v);
    for(let i=0;i<7;i++) tone(280+Math.random()*420,.12+Math.random()*.1,'square',.012,Math.random()*120-40,Math.random()*.6); },
  gasp(){ noiseHit({dur:.8,freq:520,q:.8,vol:.1,slide:-220,attack:.12,bus:busAmb}); },
  bell(){ const f=392;
    [1,2.42,3.87,5.4].forEach((m,i)=>tone(f*m,2.6-i*.5,'sine',.05*Math.pow(.6,i)));
    noiseHit({dur:.04,freq:5000,type:'highpass',vol:.03}); },
  tick(){ tone(880,.035,'sine',.022); },
};
/* 环境声与生成乐 */
const SND={inited:false,windG:null,crowdG:null,droneG:null,phraseT:2.5,drumT:1,hoofT:0};
function ambInit(){
  if(SND.inited||!AC) return;
  SND.inited=true;
  try{
    const wind=AC.createBufferSource(); wind.buffer=noiseBuffer(); wind.loop=true;
    const wf=AC.createBiquadFilter(); wf.type='lowpass'; wf.frequency.value=240; wf.Q.value=.4;
    SND.windG=AC.createGain(); SND.windG.gain.value=0;
    wind.connect(wf); wf.connect(SND.windG); SND.windG.connect(busAmb); wind.start();
    const wl=AC.createOscillator(); wl.frequency.value=.11;
    const wlg=AC.createGain(); wlg.gain.value=110;
    wl.connect(wlg); wlg.connect(wf.frequency); wl.start();
    const crowd=AC.createBufferSource(); crowd.buffer=noiseBuffer(); crowd.loop=true; crowd.playbackRate.value=.8;
    const cf=AC.createBiquadFilter(); cf.type='bandpass'; cf.frequency.value=560; cf.Q.value=.6;
    SND.crowdG=AC.createGain(); SND.crowdG.gain.value=0;
    crowd.connect(cf); cf.connect(SND.crowdG); SND.crowdG.connect(busAmb); crowd.start();
    SND.droneG=AC.createGain(); SND.droneG.gain.value=0; SND.droneG.connect(busMus);
    for(const [f,v] of [[73.42,.5],[110,.3]]){
      const o=AC.createOscillator(); o.type='triangle'; o.frequency.value=f;
      const og=AC.createGain(); og.gain.value=v;
      o.connect(og); og.connect(SND.droneG); o.start();
    }
  }catch(e){}
}
const LUTE=[293.66,329.63,349.23,392,440,523.25,587.33]; /* D 多利亚调式 */
function sndTick(dt){
  if(!AC) return;
  ambInit();
  let wind=0,crowd=0,drone=0;
  if(G.scene==='map'){ wind=1; drone=.7; }
  else if(G.scene==='title'){ wind=.6; drone=1.2; }
  else if(G.scene==='duel'){ const wild=duel&&duel.foeId==='brigand'; crowd=wild?0:1; wind=wild?.9:.2; }
  else if(G.scene==='joust'){ crowd=1.25; wind=.25; }
  else if(G.scene==='finale'){ drone=1.6; }
  const k=1-Math.exp(-dt*1.4);
  if(SND.windG) SND.windG.gain.value+=(wind*.3-SND.windG.gain.value)*k;
  if(SND.crowdG) SND.crowdG.gain.value+=(crowd*.14-SND.crowdG.gain.value)*k;
  if(SND.droneG) SND.droneG.gain.value+=(drone*.09-SND.droneG.gain.value)*k;
  /* 琉特琴散句（标题/行游） */
  if(!muted&&(G.scene==='title'||G.scene==='map')){
    SND.phraseT-=dt;
    if(SND.phraseT<=0){
      let at=0, idx=(Math.random()*LUTE.length)|0;
      const n=3+((Math.random()*4)|0);
      for(let i=0;i<n;i++){
        pluck(LUTE[idx]*(Math.random()<.22?.5:1),.09,at);
        at+=.3+Math.random()*.45;
        idx=clamp(idx+((Math.random()*3)|0)-1,0,LUTE.length-1);
      }
      SND.phraseT=5.5+Math.random()*6;
    }
  }
  /* 决斗战鼓 */
  if(G.scene==='duel'&&duel&&!duel.over&&duel.phase==='fight'){
    SND.drumT-=dt;
    if(SND.drumT<=0){ sfx.drum(.7); SND.drumT=2.4; }
  }
  /* 冲锋鼓点：越近越急 */
  if(G.scene==='joust'&&joust&&joust.phase==='charge'){
    SND.drumT-=dt;
    if(SND.drumT<=0){ sfx.drum(1); SND.drumT=clamp((joust.ex-joust.px)/14*.85,.16,.85); }
  }
  /* 行游马蹄 */
  if(G.scene==='map'&&player.moving){
    SND.hoofT-=dt;
    if(SND.hoofT<=0){ sfx.hoof(.45); SND.hoofT=.17; }
  }
}
$('#mutebtn').addEventListener('click',()=>{
  muted=!muted;
  if(master) master.gain.value=muted?0:1;
  $('#mutebtn').textContent=muted?'∅':'♪';
});

/* ================= 游戏状态 ================= */
const G={
  scene:'title',
  v:{ren:0, yi:0, li:0, zhi:0, xin:0, shendu:0},
  coins:8, deeds:[], hiddenDeeds:[], stains:[], oaths:[], flags:{}, round:0,
};
function deed(t){ G.deeds.push(t); }
function stain(t){ G.stains.push(t); }
function deed_once(key,text){ if(!G.flags['deed_'+key]){ G.flags['deed_'+key]=true; deed(text); } }
const MAP_HINT='方向键 / WASD 骑行 · 金标为未访之地 · 东北方为比武场';

/* ================= HUD / 挂件 ================= */
function hud(){
  const el=$('#hud');
  if(G.scene==='map'){
    el.innerHTML=`<span class="chip">钱袋 · ${G.coins} 银</span>
      <span class="chip">${G.oaths.length?('誓约 · '+G.oaths.length+' 则'):'圣奥仑大会 · 三日后'}</span>`;
  }else el.innerHTML='';
}
let bannerT=null;
function banner(t,ms=1300){
  const b=$('#banner'); b.textContent=t; b.style.opacity=1;
  clearTimeout(bannerT); bannerT=setTimeout(()=>b.style.opacity=0,ms);
}
let capT=null;
function caption(t,ms=3200){
  const c=$('#caption'); c.querySelector('.inner').textContent=t; c.style.opacity=1;
  clearTimeout(capT); capT=setTimeout(()=>c.style.opacity=0,ms);
}
const caption2=t=>caption(t,1500);
function hint(t){ $('#hint').textContent=t||''; }

/* ================= 面板 ================= */
const overlay=$('#overlay'), panelbox=$('#panelbox');
let panelOpen=false;
function showPanel({title,body,choices,quiet}){
  panelOpen=true; overlay.classList.add('show');
  let html=`<h2>${title}</h2><div class="rule"></div>`;
  for(const p of body) html+=`<p>${p}</p>`;
  if(quiet) html+=`<p class="quiet">${quiet}</p>`;
  html+=`<div class="choices"></div>`;
  panelbox.innerHTML=html;
  const box=panelbox.querySelector('.choices');
  choices.forEach(c=>{
    const b=document.createElement('button');
    b.innerHTML=c.label+(c.sub?`<span class="sub">${c.sub}</span>`:'');
    if(c.disabled) b.disabled=true;
    b.addEventListener('click',()=>{ sfx.tick(); closePanel(); c.fx&&c.fx(); });
    box.appendChild(b);
  });
  const first=box.querySelector('button:not(:disabled)'); first&&first.focus();
}
function closePanel(){ panelOpen=false; overlay.classList.remove('show'); hud(); }

/* ================= 输入 ================= */
const keys={}, pressed={};
addEventListener('keydown',e=>{
  if(panelOpen) return;
  keys[e.code]=true;
  if(!e.repeat) pressed[e.code]=true;
  if(['ArrowUp','ArrowDown','ArrowLeft','ArrowRight','Space'].includes(e.code)) e.preventDefault();
});
addEventListener('keyup',e=>keys[e.code]=false);
function clearPressed(){ for(const k in pressed) delete pressed[k]; }
const isTouch=matchMedia('(pointer: coarse)').matches||('ontouchstart' in window);
if(isTouch){
  document.body.classList.add('touch');
  const defs=[
    {t:'◀',x:24,b:118,k:'KeyA'},{t:'▶',x:98,b:118,k:'KeyD'},
    {t:'▲',x:61,b:186,k:'KeyW'},{t:'▼',x:61,b:50,k:'KeyS'},
    {t:'击',r:30,b:140,k:'KeyJ'},{t:'撞',r:102,b:92,k:'KeyK'},
  ];
  const tc=$('#touch');
  defs.forEach(d=>{
    const b=document.createElement('div'); b.className='tbtn'; b.textContent=d.t;
    if(d.x!=null) b.style.left=d.x+'px'; else b.style.right=d.r+'px';
    b.style.bottom=d.b+'px';
    b.addEventListener('pointerdown',e=>{e.preventDefault(); keys[d.k]=true; pressed[d.k]=true;});
    b.addEventListener('pointerup',()=>keys[d.k]=false);
    b.addEventListener('pointerleave',()=>keys[d.k]=false);
    tc.appendChild(b);
  });
}

/* ================= 渲染器 ================= */
const renderer=new THREE.WebGLRenderer({antialias:true});
renderer.setPixelRatio(Math.min(devicePixelRatio,2));
renderer.setSize(innerWidth,innerHeight);
renderer.shadowMap.enabled=true;
renderer.shadowMap.type=THREE.PCFSoftShadowMap;
renderer.toneMapping=THREE.ACESFilmicToneMapping;
renderer.toneMappingExposure=1.08;
$('#app').appendChild(renderer.domElement);
const camera=new THREE.PerspectiveCamera(46,innerWidth/innerHeight,.1,400);
addEventListener('resize',()=>{
  camera.aspect=innerWidth/innerHeight; camera.updateProjectionMatrix();
  renderer.setSize(innerWidth,innerHeight);
});

/* ================= 程序纹理 ================= */
function noiseCanvas(w,h,base,blotches){
  const c=document.createElement('canvas'); c.width=w; c.height=h;
  const x=c.getContext('2d');
  x.fillStyle=base; x.fillRect(0,0,w,h);
  for(const [col,n,r0,r1,a] of blotches){
    for(let i=0;i<n;i++){
      x.fillStyle=col; x.globalAlpha=a*(0.4+Math.random()*0.6);
      x.beginPath();
      x.ellipse(Math.random()*w,Math.random()*h,r0+Math.random()*r1,(r0+Math.random()*r1)*0.6,Math.random()*3,0,7);
      x.fill();
    }
  }
  x.globalAlpha=1;
  return c;
}
function tex(c,repeat){
  const t=new THREE.CanvasTexture(c);
  t.colorSpace=THREE.SRGBColorSpace;
  if(repeat){ t.wrapS=t.wrapT=THREE.RepeatWrapping; t.repeat.set(repeat,repeat); }
  t.anisotropy=4;
  return t;
}
function skyDome(scene,top,mid,bottom){
  const c=document.createElement('canvas'); c.width=4; c.height=512;
  const x=c.getContext('2d');
  const g=x.createLinearGradient(0,0,0,512);
  g.addColorStop(0,top); g.addColorStop(0.55,mid); g.addColorStop(1,bottom);
  x.fillStyle=g; x.fillRect(0,0,4,512);
  const t=new THREE.CanvasTexture(c); t.colorSpace=THREE.SRGBColorSpace;
  const dome=new THREE.Mesh(new THREE.SphereGeometry(320,24,16),
    new THREE.MeshBasicMaterial({map:t,side:THREE.BackSide,fog:false}));
  scene.add(dome);
  return dome;
}
function cloudSprites(scene,n,yBase){
  const c=document.createElement('canvas'); c.width=256; c.height=128;
  const x=c.getContext('2d');
  for(let i=0;i<9;i++){
    const g=x.createRadialGradient(40+Math.random()*176,40+Math.random()*48,4,40+Math.random()*176,64,44);
    g.addColorStop(0,'rgba(255,252,246,.85)'); g.addColorStop(1,'rgba(255,252,246,0)');
    x.fillStyle=g; x.fillRect(0,0,256,128);
  }
  const t=new THREE.CanvasTexture(c); t.colorSpace=THREE.SRGBColorSpace;
  for(let i=0;i<n;i++){
    const m=new THREE.Sprite(new THREE.SpriteMaterial({map:t,transparent:true,opacity:.7,fog:false}));
    const s=30+Math.random()*40;
    m.scale.set(s,s*0.42,1);
    m.position.set((Math.random()-0.5)*400, yBase+Math.random()*30, (Math.random()-0.5)*400);
    scene.add(m);
  }
}
function makeLabel(text,color='#E9E1CE'){
  const c=document.createElement('canvas'); c.width=384; c.height=96;
  const x=c.getContext('2d');
  x.font='600 52px "Kaiti SC","STKaiti","KaiTi",serif';
  x.textAlign='center'; x.textBaseline='middle';
  x.shadowColor='rgba(0,0,0,.9)'; x.shadowBlur=10;
  x.fillStyle=color; x.fillText(text,192,48);
  const t=new THREE.CanvasTexture(c); t.colorSpace=THREE.SRGBColorSpace;
  const sp=new THREE.Sprite(new THREE.SpriteMaterial({map:t,transparent:true,depthWrite:false}));
  sp.scale.set(4.4,1.1,1);
  return sp;
}

/* ================= 材质 ================= */
const M={
  armor:new THREE.MeshStandardMaterial({color:0x8f9298,metalness:.9,roughness:.32}),
  armorDark:new THREE.MeshStandardMaterial({color:0x4c5157,metalness:.85,roughness:.4}),
  leather:new THREE.MeshStandardMaterial({color:0x5a4128,roughness:.9}),
  wood:new THREE.MeshStandardMaterial({color:0x6d5233,roughness:.92}),
  woodDark:new THREE.MeshStandardMaterial({color:0x4a3722,roughness:.95}),
  blade:new THREE.MeshStandardMaterial({color:0xd6dade,metalness:.95,roughness:.18}),
  gold:new THREE.MeshStandardMaterial({color:0xC9A227,metalness:.8,roughness:.35}),
};

/* ================= 骨骼模型加载（KayKit Adventurers, CC0） ================= */
const GLTFS={};            /* key -> {scene, animations} */
let modelsReady=false;
function b64buf(b64){
  const bin=atob(b64), a=new Uint8Array(bin.length);
  for(let i=0;i<bin.length;i++) a[i]=bin.charCodeAt(i);
  return a.buffer;
}
function loadModels(){
  const loader=new GLTFLoader();
  return Promise.all(Object.entries(MODELS_B64).map(([key,b64])=>
    new Promise((res,rej)=>loader.parse(b64buf(b64),'',g=>{GLTFS[key]=g;res();},rej))
  )).then(()=>{ modelsReady=true; });
}
/* 各模型的可挂配件全集（用于显隐控制） */
const ATTACH={
  knight:['1H_Sword','2H_Sword','1H_Sword_Offhand','Badge_Shield','Rectangle_Shield','Round_Shield','Spike_Shield','Knight_Helmet','Knight_Cape'],
  rogue:['Knife','Knife_Offhand','1H_Crossbow','2H_Crossbow','Rogue_Cape','Rogue_Head_Hooded'],
  barbarian:['1H_Axe','2H_Axe','1H_Axe_Offhand','Barbarian_Round_Shield','Barbarian_Hat','Barbarian_Cape'],
};
const ATKS=['1H_Melee_Attack_Chop','1H_Melee_Attack_Slice_Horizontal','1H_Melee_Attack_Stab'];
class Actor{
  constructor(modelKey,{tint,show,scale=1}={}){
    const g=GLTFS[modelKey];
    this.root=new THREE.Group();
    this.model=skClone(g.scene);
    this.mats=[];
    this.model.traverse(o=>{
      if(o.isMesh||o.isSkinnedMesh){
        o.castShadow=true; o.receiveShadow=true;
        o.material=o.material.clone();
        if(tint) o.material.color.multiply(new THREE.Color(tint));
        this.mats.push(o.material);
      }
    });
    if(show){
      for(const nm of ATTACH[modelKey]){
        const n=this.model.getObjectByName(nm);
        if(n) n.visible=show.includes(nm);
      }
    }
    /* 统一身高约 1.85 */
    const bb=new THREE.Box3().setFromObject(this.model);
    const h=bb.max.y-bb.min.y;
    const s=(1.85/h)*scale;
    this.model.scale.setScalar(s);
    this.model.position.y=-bb.min.y*s;
    this.root.add(this.model);
    this.mixer=new THREE.AnimationMixer(this.model);
    this.actions={};
    for(const clip of g.animations) this.actions[clip.name]=this.mixer.clipAction(clip);
    this.key=null; this.cur=null;
    this.armBone=this.model.getObjectByName('upperarm.r');
    this.mixer.addEventListener('finished',()=>{
      if(['hitreact','blockreact','stagger','swing0','swing1','swing2'].includes(this.key)) this.key=null;
    });
  }
  play(name,{loop=true,clamp=false,fade=0.14,timeScale=1,from=0}={}){
    const a=this.actions[name];
    if(!a) return null;
    a.reset();
    a.setLoop(loop?THREE.LoopRepeat:THREE.LoopOnce, Infinity);
    a.clampWhenFinished=clamp;
    a.timeScale=timeScale;
    a.time=from;
    a.enabled=true;
    if(this.cur&&this.cur!==a){ a.crossFadeFrom(this.cur,fade,false); }
    a.play();
    this.cur=a;
    return a;
  }
  setEmissive(v){
    const i=Math.min(v*0.45,0.32);
    for(const m of this.mats){ if(m.emissive){ m.emissive.setRGB(.5,.04,0); m.emissiveIntensity=i; } }
  }
}
/* 决斗状态 → 动画 */
function syncActor(actor,f,dt){
  const moving=Math.abs(f.vx||0)>1;
  let key;
  if(f.phaseSalute) key='salute';
  else if(f.state==='yield') key='yield';
  else if(f.state==='windup') key='windup'+f.strikeStance;
  else if(f.state==='strike'||f.state==='recover') key='swing'+f.strikeStance;
  else if(f.state==='stagger') key='stagger';
  else if(f.exhaust>0) key='exhaust';
  else if(moving) key=(f.vx*f.face>0)?'walk':'back';
  else key='guard';
  if(f._hitPulse){ f._hitPulse=false; key='hitreact'; actor.key=null; }
  if(f._blockPulse){ f._blockPulse=false; key='blockreact'; actor.key=null; }
  if(key!==actor.key){
    const prev=actor.key;
    actor.key=key;
    if(key==='salute') actor.play('Cheer',{loop:false,clamp:true,timeScale:.9});
    else if(key==='yield') actor.play('Sit_Floor_Down',{loop:false,clamp:true,timeScale:.85});
    else if(key.startsWith('windup')){
      const clip=ATKS[f.strikeStance];
      const a=actor.play(clip,{loop:false,clamp:true,fade:.08});
      if(a){
        const dur=a.getClip().duration;
        const windup=Math.max(f.t>0?f.t:0.36,0.08);
        a.timeScale=(dur*0.3)/windup;      /* 起手段缓慢抬剑 */
      }
    }
    else if(key.startsWith('swing')){
      const a=actor.actions[ATKS[f.strikeStance]];
      if(a&&(prev||'').startsWith('windup')){ a.timeScale=2.8; }  /* 挥击段爆发 */
      else if(a){ actor.play(ATKS[f.strikeStance],{loop:false,clamp:true,timeScale:2.8,from:a.getClip().duration*0.3}); }
    }
    else if(key==='stagger') actor.play('Hit_B',{loop:false,clamp:true,fade:.06});
    else if(key==='hitreact') actor.play('Hit_A',{loop:false,fade:.05,timeScale:1.7});
    else if(key==='blockreact') actor.play('Block_Hit',{loop:false,fade:.05,timeScale:1.4});
    else if(key==='exhaust') actor.play('Idle',{timeScale:.4});
    else if(key==='walk') actor.play('Walking_A',{timeScale:1.35});
    else if(key==='back') actor.play('Walking_Backwards',{timeScale:1.25});
    else actor.play('Blocking');
  }
  actor.mixer.update(dt);
  /* 守势时以持剑臂高低区分三段架势（骨骼后处理） */
  if((key==='guard'||key==='walk'||key==='back')&&actor.armBone){
    actor.armBone.rotation.x+=[-0.55,0,0.5][f.stance];
  }
  actor.setEmissive(f.hurtFlash>0?Math.max(0,f.hurtFlash*2):0);
}
/* ================= 马与骑者（行游） ================= */
function buildHorse(coatHex=0x5c452c){
  const root=new THREE.Group();
  const cast=m=>{ m.castShadow=true; return m; };
  const coat=new THREE.MeshStandardMaterial({color:coatHex,roughness:.85});
  const body=cast(new THREE.Mesh(new THREE.CapsuleGeometry(.34,1.05,6,12),coat));
  body.rotation.z=Math.PI/2; body.position.y=0.98; root.add(body);
  const neck=cast(new THREE.Mesh(new THREE.CylinderGeometry(.13,.2,.62,10),coat));
  neck.position.set(.62,1.32,0); neck.rotation.z=-0.65; root.add(neck);
  const head=cast(new THREE.Mesh(new THREE.BoxGeometry(.42,.17,.15),coat));
  head.position.set(.92,1.56,0); head.rotation.z=-0.25; root.add(head);
  for(const side of [-1,1]){
    const ear=cast(new THREE.Mesh(new THREE.ConeGeometry(.035,.11,6),coat));
    ear.position.set(.78,1.7,side*0.06); root.add(ear);
  }
  const mane=cast(new THREE.Mesh(new THREE.BoxGeometry(.5,.3,.05),new THREE.MeshStandardMaterial({color:0x2b2118,roughness:1})));
  mane.position.set(.58,1.46,0); mane.rotation.z=-0.65; root.add(mane);
  const tail=cast(new THREE.Mesh(new THREE.ConeGeometry(.07,.6,8),new THREE.MeshStandardMaterial({color:0x2b2118,roughness:1})));
  tail.position.set(-.72,0.85,0); tail.rotation.z=2.6; root.add(tail);
  const legs=[];
  for(const [lx,lz] of [[.42,.16],[.42,-.16],[-.42,.16],[-.42,-.16]]){
    const g=new THREE.Group(); g.position.set(lx,0.75,lz);
    const leg=cast(new THREE.Mesh(new THREE.CylinderGeometry(.05,.04,.75,8),coat));
    leg.position.y=-0.37; g.add(leg);
    root.add(g); legs.push(g);
  }
  /* 鞍与旧程序化骑者（骨骼模型就绪后替换） */
  const saddle=cast(new THREE.Mesh(new THREE.BoxGeometry(.4,.08,.34),M.leather));
  saddle.position.set(.05,1.3,0); root.add(saddle);
  const riderOld=new THREE.Group(); root.add(riderOld);
  const rTorso=cast(new THREE.Mesh(new THREE.CapsuleGeometry(.14,.32,4,10),new THREE.MeshStandardMaterial({color:0x2E4A66,roughness:.85})));
  rTorso.position.set(.05,1.66,0); riderOld.add(rTorso);
  const rHead=cast(new THREE.Mesh(new THREE.SphereGeometry(.09,10,8),M.armor));
  rHead.position.set(.05,1.98,0); riderOld.add(rHead);
  const lance=cast(new THREE.Mesh(new THREE.CylinderGeometry(.015,.025,2.2,6),M.wood));
  lance.position.set(.1,1.7,.24); lance.rotation.z=-1.25; riderOld.add(lance);
  const shp=new THREE.Shape();
  shp.moveTo(-.17,.2); shp.quadraticCurveTo(0,.25,.17,.2);
  shp.quadraticCurveTo(.18,-.08,0,-.24); shp.quadraticCurveTo(-.18,-.08,-.17,.2);
  const sh=cast(new THREE.Mesh(new THREE.ExtrudeGeometry(shp,{depth:.03,bevelEnabled:false}),
    new THREE.MeshStandardMaterial({color:0xC9A227,roughness:.55,metalness:.3})));
  sh.position.set(.0,1.62,-.2); sh.rotation.y=Math.PI/2*0.9; riderOld.add(sh);
  root.traverse(o=>{ if(o.isMesh) o.receiveShadow=true; });
  return {root,legs,riderOld};
}

/* ================= 场景：行游地图 ================= */
const S=1/60;                    /* px→世界 */
const MAP={w:1700,h:1100};
const mapCenter=[850,550];
const wx=x=>(x-mapCenter[0])*S, wz=y=>(y-mapCenter[1])*S;
const player={x:210,y:930,a:0,speed:175};
const LOCS=[
  {id:'village', x:520,y:430, r:70, name:'沙溪村', done:false},
  {id:'forest',  x:860,y:250, r:80, name:'黑桦林', done:false},
  {id:'ford',    x:1030,y:780,r:70, name:'苇渡口', done:false},
  {id:'field',   x:1450,y:330,r:85, name:'圣奥仑比武场', done:false},
];
const TREES=[]; { let seed=7; const rnd=()=>{seed=(seed*16807)%2147483647; return seed/2147483647;};
  for(let i=0;i<46;i++) TREES.push({x:700+rnd()*380,y:120+rnd()*300,s:.8+rnd()*.7});
  for(let i=0;i<20;i++) TREES.push({x:120+rnd()*350,y:120+rnd()*300,s:.7+rnd()*.8});
  for(let i=0;i<26;i++){ /* 边缘散树 */
    const edge=Math.floor(rnd()*4);
    const x=edge<2?rnd()*1700:(edge===2?40+rnd()*120:1540+rnd()*140);
    const y=edge===0?30+rnd()*90:(edge===1?980+rnd()*100:rnd()*1100);
    TREES.push({x,y,s:.8+rnd()*.9});
  }
}
const roadPts=[[210,930],[380,760],[520,470],[700,380],[860,300],[1030,740],[1240,560],[1450,370]];

const mapScene=new THREE.Scene();
mapScene.fog=new THREE.Fog(0xC8D4E0,26,150);
skyDome(mapScene,'#5E86BC','#A8C0DC','#EADFC2');
cloudSprites(mapScene,12,60);
{
  const sun=new THREE.DirectionalLight(0xFFEAC2,2.6);
  sun.position.set(18,26,10); sun.castShadow=true;
  sun.shadow.mapSize.set(2048,2048);
  sun.shadow.camera.left=-22; sun.shadow.camera.right=22;
  sun.shadow.camera.top=22; sun.shadow.camera.bottom=-22;
  sun.shadow.camera.far=90; sun.shadow.bias=-0.0015;
  mapScene.add(sun); mapScene.add(sun.target);
  mapScene.userData.sun=sun;
  mapScene.add(new THREE.HemisphereLight(0xBBD0E8,0x4A5D3A,0.85));
}
/* 地面：草地纹理 + 路与河直接绘制 */
{
  const gc=document.createElement('canvas'); gc.width=2048; gc.height=1326;
  const x=gc.getContext('2d');
  const cx=2048/1700, cy=1326/1100;
  x.fillStyle='#57683B'; x.fillRect(0,0,2048,1326);
  for(let i=0;i<2600;i++){
    x.fillStyle=['#4E5F34','#617242','#526B38','#6A7A48'][i%4];
    x.globalAlpha=0.25+Math.random()*0.4;
    x.beginPath();
    x.ellipse(Math.random()*2048,Math.random()*1326,6+Math.random()*26,4+Math.random()*14,Math.random()*3,0,7);
    x.fill();
  }
  x.globalAlpha=1;
  /* 河 */
  x.strokeStyle='#5E7C90'; x.lineWidth=52*cx*0.55; x.lineCap='round';
  x.beginPath(); x.moveTo(760*cx,1326);
  x.quadraticCurveTo(980*cx,830*cy,1120*cx,660*cy);
  x.quadraticCurveTo(1260*cx,480*cy,2048,430*cy); x.stroke();
  x.strokeStyle='#6E8CA0'; x.lineWidth=30*cx*0.55;
  x.beginPath(); x.moveTo(760*cx,1326);
  x.quadraticCurveTo(980*cx,830*cy,1120*cx,660*cy);
  x.quadraticCurveTo(1260*cx,480*cy,2048,430*cy); x.stroke();
  /* 路 */
  x.strokeStyle='#8B7A55'; x.lineWidth=30*cx*0.55; x.lineJoin='round'; x.lineCap='round';
  x.beginPath(); x.moveTo(roadPts[0][0]*cx,roadPts[0][1]*cy);
  for(const p of roadPts.slice(1)) x.lineTo(p[0]*cx,p[1]*cy);
  x.stroke();
  x.strokeStyle='#7A6A48'; x.lineWidth=16*cx*0.55;
  x.beginPath(); x.moveTo(roadPts[0][0]*cx,roadPts[0][1]*cy);
  for(const p of roadPts.slice(1)) x.lineTo(p[0]*cx,p[1]*cy);
  x.stroke();
  /* 场地泥土 */
  for(const [lx,ly,lr] of [[180,950,120],[1450,330,150],[470,410,130]]){
    x.fillStyle='#7A6A48'; x.globalAlpha=.5;
    x.beginPath(); x.ellipse(lx*cx,ly*cy,lr*cx*.6,lr*cy*.5,0,0,7); x.fill();
  }
  x.globalAlpha=1;
  const groundTex=tex(gc);
  const ground=new THREE.Mesh(new THREE.PlaneGeometry(MAP.w*S,MAP.h*S,1,1),
    new THREE.MeshStandardMaterial({map:groundTex,roughness:.95}));
  ground.rotation.x=-Math.PI/2; ground.receiveShadow=true;
  mapScene.add(ground);
  /* 外圈草地 */
  const outer=new THREE.Mesh(new THREE.CircleGeometry(260,32),
    new THREE.MeshStandardMaterial({color:0x57683B,roughness:1}));
  outer.rotation.x=-Math.PI/2; outer.position.y=-0.02; outer.receiveShadow=true;
  mapScene.add(outer);
}
/* 远山 */
for(let i=0;i<14;i++){
  const a=i/14*Math.PI*2;
  const r=120+((i*37)%40);
  const h=18+((i*53)%22);
  const m=new THREE.Mesh(new THREE.ConeGeometry(26+(i*29)%20,h,7),
    new THREE.MeshStandardMaterial({color:0x6E7B8A,roughness:1,flatShading:true}));
  m.position.set(Math.cos(a)*r,h/2-2,Math.sin(a)*r);
  mapScene.add(m);
}
/* 树 */
{
  const trunkGeo=new THREE.CylinderGeometry(.09,.13,1,7);
  const folGeo=new THREE.ConeGeometry(.85,1.7,8);
  const folMat=new THREE.MeshStandardMaterial({color:0x3E5A2E,roughness:.95,flatShading:true});
  const folMat2=new THREE.MeshStandardMaterial({color:0x4C6B38,roughness:.95,flatShading:true});
  for(const t of TREES){
    const g=new THREE.Group();
    const trunk=new THREE.Mesh(trunkGeo,M.woodDark); trunk.position.y=.5; trunk.castShadow=true; g.add(trunk);
    const f1=new THREE.Mesh(folGeo,(t.x+t.y)%2?folMat:folMat2); f1.position.y=1.55; f1.castShadow=true; g.add(f1);
    const f2=new THREE.Mesh(folGeo,folMat2); f2.scale.setScalar(.7); f2.position.y=2.25; f2.castShadow=true; g.add(f2);
    g.scale.setScalar(t.s*1.15);
    g.position.set(wx(t.x),0,wz(t.y));
    g.rotation.y=(t.x*7+t.y*13)%6;
    mapScene.add(g);
  }
}
/* 村舍 */
function house(px,py,rot){
  const g=new THREE.Group();
  const wallMat=new THREE.MeshStandardMaterial({color:0xC9B69A,roughness:.9});
  const wall=new THREE.Mesh(new THREE.BoxGeometry(1.5,.9,1.1),wallMat);
  wall.position.y=.45; wall.castShadow=true; wall.receiveShadow=true; g.add(wall);
  const roofMat=new THREE.MeshStandardMaterial({color:0x8A4B32,roughness:.85});
  const roof=new THREE.Mesh(new THREE.ConeGeometry(1.12,.62,4),roofMat);
  roof.position.y=1.2; roof.rotation.y=Math.PI/4; roof.scale.set(1.25,1,.95); roof.castShadow=true; g.add(roof);
  const chim=new THREE.Mesh(new THREE.BoxGeometry(.14,.4,.14),new THREE.MeshStandardMaterial({color:0x7A7A78,roughness:.9}));
  chim.position.set(.4,1.35,.2); g.add(chim);
  g.position.set(wx(px),0,wz(py)); g.rotation.y=rot;
  mapScene.add(g);
}
house(470,400,0.2); house(540,430,-0.4); house(495,465,0.9); house(560,480,0.1);
/* 营地帐篷 */
function tent(px,py,hex){
  const g=new THREE.Group();
  const m=new THREE.Mesh(new THREE.ConeGeometry(.8,1.2,4),new THREE.MeshStandardMaterial({color:hex,roughness:.85}));
  m.position.y=.6; m.rotation.y=Math.PI/4; m.castShadow=true; g.add(m);
  const pole=new THREE.Mesh(new THREE.CylinderGeometry(.02,.02,.6,6),M.wood);
  pole.position.y=1.4; g.add(pole);
  const flag=new THREE.Mesh(new THREE.PlaneGeometry(.4,.22),new THREE.MeshStandardMaterial({color:0xC9A227,side:THREE.DoubleSide,roughness:.8}));
  flag.position.set(.2,1.6,0); g.add(flag);
  g.position.set(wx(px),0,wz(py));
  mapScene.add(g);
}
tent(160,950,0x2E4A66); tent(230,975,0x6B4A2E);
/* 比武场（远景） */
{
  const g=new THREE.Group();
  for(let i=0;i<14;i++){
    const a=i/14*Math.PI*2;
    const post=new THREE.Mesh(new THREE.CylinderGeometry(.05,.05,.8,6),M.wood);
    post.position.set(Math.cos(a)*2.6,.4,Math.sin(a)*1.9); post.castShadow=true; g.add(post);
  }
  const rail=new THREE.Mesh(new THREE.TorusGeometry(2.3,.03,6,24),M.wood);
  rail.rotation.x=Math.PI/2; rail.scale.set(1,0.73,1); rail.position.y=.72; g.add(rail);
  for(const [fx,fc] of [[-2.8,0x9E2B20],[2.8,0x2E4A66]]){
    const pole=new THREE.Mesh(new THREE.CylinderGeometry(.04,.04,2.6,6),M.wood);
    pole.position.set(fx,1.3,0); g.add(pole);
    const fl=new THREE.Mesh(new THREE.PlaneGeometry(.8,.4),new THREE.MeshStandardMaterial({color:fc,side:THREE.DoubleSide,roughness:.8}));
    fl.position.set(fx+.4,2.4,0); g.add(fl);
  }
  const stand=new THREE.Mesh(new THREE.BoxGeometry(3.4,.7,.9),M.woodDark);
  stand.position.set(0,.35,-2.9); stand.castShadow=true; g.add(stand);
  g.position.set(wx(1450),0,wz(330));
  mapScene.add(g);
}
/* 渡口桥板 + 信使遗体 */
{
  const bridge=new THREE.Mesh(new THREE.BoxGeometry(1.1,.08,2.2),M.wood);
  bridge.position.set(wx(1035),.06,wz(762)); bridge.rotation.y=-0.7; bridge.castShadow=true;
  mapScene.add(bridge);
  const courier=new THREE.Group();
  const bodyM=new THREE.Mesh(new THREE.CapsuleGeometry(.13,.5,4,8),new THREE.MeshStandardMaterial({color:0x3A4A5A,roughness:.9}));
  bodyM.rotation.z=Math.PI/2*.94; bodyM.position.y=.13; courier.add(bodyM);
  const satchel=new THREE.Mesh(new THREE.BoxGeometry(.2,.12,.14),M.leather);
  satchel.position.set(.35,.1,.15); courier.add(satchel);
  courier.position.set(wx(1000),0,wz(820)); courier.rotation.y=.8;
  mapScene.add(courier);
  mapScene.userData.courier=courier;
  /* 芦苇 */
  const reedMat=new THREE.MeshStandardMaterial({color:0x8A9A5B,roughness:1});
  for(let i=0;i<40;i++){
    const r=new THREE.Mesh(new THREE.CylinderGeometry(.012,.02,.7+Math.random()*.5,4),reedMat);
    const a=Math.random()*Math.PI*2, rr=Math.random()*1.6;
    r.position.set(wx(1000)+Math.cos(a)*rr,.4,wz(830)+Math.sin(a)*rr);
    r.rotation.z=(Math.random()-.5)*.2;
    mapScene.add(r);
  }
}
/* 地点浮标与地名 */
const markers=[];
for(const l of LOCS){
  const g=new THREE.Group();
  const d=new THREE.Mesh(new THREE.OctahedronGeometry(.22),new THREE.MeshStandardMaterial({color:0xC9A227,metalness:.7,roughness:.3,emissive:0x6b5210,emissiveIntensity:.6}));
  d.position.y=2.6; g.add(d);
  const label=makeLabel(l.name);
  label.position.y=3.4; g.add(label);
  g.position.set(wx(l.x),0,wz(l.y));
  mapScene.add(g);
  markers.push({loc:l,g,d});
}
/* 马 */
const horse=buildHorse();
mapScene.add(horse.root);
let horseYaw=0;

/* ================= 场景：决斗竞技场 ================= */
const duelScene=new THREE.Scene();
duelScene.fog=new THREE.Fog(0xD8CBAE,30,120);
skyDome(duelScene,'#6E93C4','#C4B896','#E8D9B8');
cloudSprites(duelScene,8,55);
{
  const sun=new THREE.DirectionalLight(0xFFE2B0,2.8);
  sun.position.set(-14,20,12); sun.castShadow=true;
  sun.shadow.mapSize.set(2048,2048);
  sun.shadow.camera.left=-14; sun.shadow.camera.right=14;
  sun.shadow.camera.top=14; sun.shadow.camera.bottom=-14;
  sun.shadow.camera.far=70; sun.shadow.bias=-0.0015;
  duelScene.add(sun);
  duelScene.add(new THREE.HemisphereLight(0xC8D8E8,0x6B5B3E,0.8));
}
{
  const sand=tex(noiseCanvas(512,512,'#B39A6B',[
    ['#A38A5B',260,6,20,.5],['#C4AB7C',200,8,26,.4],['#8F7A50',140,4,14,.5]]),4);
  const ground=new THREE.Mesh(new THREE.CircleGeometry(60,48),
    new THREE.MeshStandardMaterial({map:sand,roughness:.98}));
  ground.rotation.x=-Math.PI/2; ground.receiveShadow=true;
  duelScene.add(ground);
  /* 场心划线 */
  const line=new THREE.Mesh(new THREE.RingGeometry(7.6,7.75,64),
    new THREE.MeshStandardMaterial({color:0xE8DCC3,roughness:1}));
  line.rotation.x=-Math.PI/2; line.position.y=.01;
  duelScene.add(line);
  /* 栅栏 */
  for(let i=0;i<26;i++){
    const a=i/26*Math.PI*2;
    const post=new THREE.Mesh(new THREE.CylinderGeometry(.07,.07,1.1,7),M.wood);
    post.position.set(Math.cos(a)*8.4,.55,Math.sin(a)*8.4); post.castShadow=true;
    duelScene.add(post);
  }
  const rail=new THREE.Mesh(new THREE.TorusGeometry(8.4,.045,7,48),M.wood);
  rail.rotation.x=Math.PI/2; rail.position.y=1.0; duelScene.add(rail);
  const rail2=rail.clone(); rail2.position.y=.55; duelScene.add(rail2);
  /* 看台（两侧弧形）+ 人群 */
  const crowdColors=[0x9E2B20,0x2E4A66,0x6B7A3A,0xB08A3E,0x7A4A6B,0x4A6B7A,0xC9B69A,0x5B4A32];
  for(const side of [-1,1]){
    for(let tier=0;tier<3;tier++){
      const rad=10.6+tier*1.15;
      const geo=new THREE.CylinderGeometry(rad,rad,0.9,40,1,true,side>0?Math.PI*0.18:Math.PI*1.18,Math.PI*0.64);
      const m=new THREE.Mesh(geo,new THREE.MeshStandardMaterial({color:0x5B4630,roughness:.95,side:THREE.DoubleSide}));
      m.position.y=.45+tier*.75;
      duelScene.add(m);
      /* 人群小方块 */
      const n=26;
      const inst=new THREE.InstancedMesh(new THREE.BoxGeometry(.22,.3,.16),
        new THREE.MeshStandardMaterial({roughness:.9}),n);
      const mat4=new THREE.Matrix4(); const col=new THREE.Color();
      for(let i=0;i<n;i++){
        const a=(side>0?Math.PI*0.20:Math.PI*1.20)+ (i/n)*Math.PI*0.60 + Math.PI/2;
        mat4.setPosition(Math.cos(a)*(rad-0.1), 1.05+tier*.75, Math.sin(a)*(rad-0.1));
        inst.setMatrixAt(i,mat4);
        col.setHex(crowdColors[(i+tier*5)%crowdColors.length]);
        inst.setColorAt(i,col);
      }
      duelScene.add(inst);
    }
  }
  /* 主看台华盖 */
  const dais=new THREE.Mesh(new THREE.BoxGeometry(4.2,1.1,2),M.woodDark);
  dais.position.set(0,.55,-11.2); duelScene.add(dais);
  const canopy=new THREE.Mesh(new THREE.BoxGeometry(4.6,.1,2.4),
    new THREE.MeshStandardMaterial({color:0x9E2B20,roughness:.85}));
  canopy.position.set(0,3.1,-11.2); duelScene.add(canopy);
  for(const px of [-2.1,2.1]){
    const pole=new THREE.Mesh(new THREE.CylinderGeometry(.05,.05,3,7),M.wood);
    pole.position.set(px,1.6,-10.4); duelScene.add(pole);
  }
  /* 旗杆 */
  duelScene.userData.flags=[];
  for(let i=0;i<6;i++){
    const a=i/6*Math.PI*2+.3;
    const pole=new THREE.Mesh(new THREE.CylinderGeometry(.05,.05,5,7),M.wood);
    pole.position.set(Math.cos(a)*9.6,2.5,Math.sin(a)*9.6);
    duelScene.add(pole);
    const fl=new THREE.Mesh(new THREE.PlaneGeometry(1.3,.6,6,1),
      new THREE.MeshStandardMaterial({color:i%2?0x9E2B20:0x2E4A66,side:THREE.DoubleSide,roughness:.85}));
    fl.position.set(Math.cos(a)*9.6+.65,4.6,Math.sin(a)*9.6);
    duelScene.add(fl);
    duelScene.userData.flags.push(fl);
  }
}
/* 决斗者（骨骼模型） */
let P_ACT=null, E_ACT=null;
const FACE_P=Math.PI/2, FACE_E=-Math.PI/2;   /* 模型朝向 +Z，转向 ±X */
const FOE_STYLE={
  brigand:{model:'rogue', show:['Knife','Rogue_Cape','Rogue_Head_Hooded']},
  talbot:{model:'barbarian', show:['1H_Axe','Barbarian_Round_Shield','Barbarian_Hat']},
  edmund:{model:'knight', show:['1H_Sword','Round_Shield','Knight_Helmet','Knight_Cape'], tint:0xd9dfe4},
  belloc:{model:'knight', show:['1H_Sword','Spike_Shield','Knight_Helmet','Knight_Cape'], tint:0x555060},
};
function ensurePlayerActor(){
  if(!P_ACT&&modelsReady){
    P_ACT=new Actor('knight',{show:['1H_Sword','Badge_Shield','Knight_Helmet','Knight_Cape']});
    P_ACT.root.rotation.y=FACE_P;
    duelScene.add(P_ACT.root);
  }
}
function setFoeActor(foeId){
  ensurePlayerActor();
  if(E_ACT) duelScene.remove(E_ACT.root);
  const st=FOE_STYLE[foeId]||FOE_STYLE.belloc;
  E_ACT=new Actor(st.model,{show:st.show,tint:st.tint});
  E_ACT.root.rotation.y=FACE_E;
  duelScene.add(E_ACT.root);
}
/* 火花粒子 */
const sparks=[];
{
  const geo=new THREE.BufferGeometry();
  const NP=26;
  geo.setAttribute('position',new THREE.BufferAttribute(new Float32Array(NP*3),3));
  const mat=new THREE.PointsMaterial({color:0xFFD873,size:.06,transparent:true,blending:THREE.AdditiveBlending,depthWrite:false});
  for(let i=0;i<3;i++){
    const p=new THREE.Points(geo.clone(),mat.clone());
    p.visible=false; duelScene.add(p);
    sparks.push({mesh:p,vel:new Float32Array(NP*3),life:0});
  }
}
function spawnSparks(pos,color){
  const s=sparks.find(s=>s.life<=0)||sparks[0];
  s.life=.45; s.mesh.visible=true;
  s.mesh.material.color.setHex(color);
  s.mesh.material.opacity=1;
  const arr=s.mesh.geometry.attributes.position.array;
  for(let i=0;i<arr.length;i+=3){
    arr[i]=pos.x; arr[i+1]=pos.y; arr[i+2]=pos.z;
    s.vel[i]=(Math.random()-.5)*4; s.vel[i+1]=Math.random()*3.2; s.vel[i+2]=(Math.random()-.5)*4;
  }
  s.mesh.geometry.attributes.position.needsUpdate=true;
}
function tickSparks(dt){
  for(const s of sparks){
    if(s.life<=0) continue;
    s.life-=dt;
    const arr=s.mesh.geometry.attributes.position.array;
    for(let i=0;i<arr.length;i+=3){
      arr[i]+=s.vel[i]*dt; arr[i+1]+=s.vel[i+1]*dt; arr[i+2]+=s.vel[i+2]*dt;
      s.vel[i+1]-=9.5*dt;
    }
    s.mesh.geometry.attributes.position.needsUpdate=true;
    s.mesh.material.opacity=Math.max(0,s.life/.45);
    if(s.life<=0) s.mesh.visible=false;
  }
}
let shake=0;

/* ================= 场景：终幕 ================= */
const finaleScene=new THREE.Scene();
finaleScene.background=new THREE.Color(0x0C0A08);
{
  const spot=new THREE.SpotLight(0xFFE2B0,140,40,.5,.5);
  spot.position.set(3,7,6); spot.castShadow=true;
  finaleScene.add(spot);
  const spot2=new THREE.SpotLight(0x8CA6BC,50,40,.7,.6);
  spot2.position.set(-6,4,3);
  finaleScene.add(spot2);
  finaleScene.add(new THREE.AmbientLight(0x241C12,2));
  const front=new THREE.PointLight(0xFFE2B0,26,24,1.6);
  front.position.set(-1,1.2,4.5);
  finaleScene.add(front);
  const floor=new THREE.Mesh(new THREE.CircleGeometry(8,40),
    new THREE.MeshStandardMaterial({color:0x1A140E,roughness:.6,metalness:.2}));
  floor.rotation.x=-Math.PI/2; floor.position.y=-1.6; floor.receiveShadow=true;
  finaleScene.add(floor);
}
let shieldMesh=null;
function buildFinaleShield(){
  const v=G.v;
  const chars=[['仁',v.ren],['义',v.yi],['礼',v.li],['智',v.zhi],['信',v.xin]];
  /* 盾面纹理（透明底上画熨斗盾形） */
  const c=document.createElement('canvas'); c.width=1024; c.height=1024;
  const x=c.getContext('2d');
  const heater=()=>{
    x.beginPath();
    x.moveTo(140,190); x.quadraticCurveTo(512,116,884,190);
    x.quadraticCurveTo(928,560,512,952);
    x.quadraticCurveTo(96,560,140,190);
    x.closePath();
  };
  const wood=x.createLinearGradient(0,0,1024,0);
  wood.addColorStop(0,'#2E2416'); wood.addColorStop(.5,'#40301C'); wood.addColorStop(1,'#2E2416');
  heater(); x.fillStyle=wood; x.fill();
  x.save(); heater(); x.clip();
  for(let i=0;i<70;i++){
    x.strokeStyle=`rgba(20,14,8,${.1+Math.random()*.2})`; x.lineWidth=1+Math.random()*3;
    x.beginPath(); x.moveTo(0,Math.random()*1024);
    x.bezierCurveTo(300,Math.random()*1024,700,Math.random()*1024,1024,Math.random()*1024);
    x.stroke();
  }
  x.restore();
  /* 金边沿盾形 */
  heater(); x.strokeStyle='#C9A227'; x.lineWidth=16; x.stroke();
  heater(); x.strokeStyle='#8A7233'; x.lineWidth=4; x.stroke();
  const seal=(sx,sy,ch,earned)=>{
    x.save(); x.translate(sx,sy);
    if(earned){
      x.fillStyle='#A63A2B';
      x.shadowColor='rgba(0,0,0,.6)'; x.shadowBlur=18;
      x.beginPath(); x.roundRect(-86,-86,172,172,14); x.fill();
      x.shadowBlur=0;
      x.strokeStyle='#C9A227'; x.lineWidth=5; x.stroke();
      x.fillStyle='#F2E3C2';
    }else{
      x.strokeStyle='rgba(180,160,120,.28)'; x.lineWidth=4;
      x.beginPath(); x.roundRect(-86,-86,172,172,14); x.stroke();
      x.fillStyle='rgba(180,160,120,.25)';
    }
    x.font='600 120px "Kaiti SC","STKaiti","KaiTi",serif';
    x.textAlign='center'; x.textBaseline='middle';
    x.fillText(ch,0,8);
    x.restore();
  };
  const pos=[[512,490],[322,300],[702,300],[352,668],[672,668]];
  chars.forEach((cc,i)=>seal(pos[i][0],pos[i][1],cc[0],cc[1]>=1));
  if(G.stains.length){
    x.save(); heater(); x.clip();
    x.strokeStyle='rgba(8,5,3,.85)'; x.lineWidth=46; x.lineCap='round';
    x.beginPath(); x.moveTo(200,200); x.lineTo(820,840); x.stroke();
    x.restore();
  }
  const faceTex=new THREE.CanvasTexture(c); faceTex.colorSpace=THREE.SRGBColorSpace;
  /* 盾体 */
  const shp=new THREE.Shape();
  shp.moveTo(-1.05,1.25); shp.quadraticCurveTo(0,1.5,1.05,1.25);
  shp.quadraticCurveTo(1.18,-.3,0,-1.45); shp.quadraticCurveTo(-1.18,-.3,-1.05,1.25);
  const geo=new THREE.ExtrudeGeometry(shp,{depth:.16,bevelEnabled:true,bevelSize:.07,bevelThickness:.05,bevelSegments:3});
  const g=new THREE.Group();
  const body=new THREE.Mesh(geo,new THREE.MeshStandardMaterial({color:0x3A2C1A,roughness:.55,metalness:.25}));
  body.castShadow=true; body.scale.set(0.76,0.8,1); body.position.y=-0.06; g.add(body);
  const face=new THREE.Mesh(new THREE.PlaneGeometry(2.6,2.6),
    new THREE.MeshStandardMaterial({map:faceTex,roughness:.5,metalness:.15,transparent:true,alphaTest:.05}));
  face.position.z=.24; g.add(face);
  if(v.shendu>=2&&!G.stains.length){
    const star=new THREE.Mesh(new THREE.OctahedronGeometry(.14),
      new THREE.MeshStandardMaterial({color:0xC9A227,metalness:.9,roughness:.2,emissive:0x8a6a10,emissiveIntensity:1.4}));
    star.position.set(0,1.62,.1); g.add(star);
  }
  g.position.set(-1.3,.4,0);
  finaleScene.add(g);
  shieldMesh=g;
}

/* ================= 决斗 HUD ================= */
const STANCES=['上段','中段','下段'];
const dhud=$('#dhud');
function duelHudShow(name){
  dhud.classList.add('show');
  $('#fc-e .nm').innerHTML=name;
}
function duelHudHide(){ dhud.classList.remove('show'); $('#roundname').textContent=''; $('#salutetip').style.display='none'; }
function duelHudTick(){
  if(!duel) return;
  const p=duel.p, e=duel.e;
  $('#fc-p .qi i').style.width=(p.resolve/p.resolveMax*100)+'%';
  $('#fc-p .ti i').style.width=p.stam+'%';
  $('#fc-e .qi i').style.width=(e.resolve/e.resolveMax*100)+'%';
  $('#fc-e .ti i').style.width=e.stam+'%';
  $('#fc-p .st').innerHTML='架势 · <b>'+STANCES[p.stance]+'</b>'+(p.exhaust>0?' <span style="color:#C96B4A">力竭</span>':'');
  $('#fc-e .st').innerHTML=(e.exhaust>0?'<span style="color:#C96B4A">力竭</span> ':'')+'<b>'+STANCES[e.stance]+'</b> · 架势';
}

/* ================= 决斗逻辑（已验证的机制） ================= */
let duel=null;
function mkFighter(o){
  return Object.assign({
    x:0, face:1, stance:1, resolve:100, resolveMax:100, stam:100, vx:0,
    state:'idle', t:0, strikeStance:1, feinted:false,
    shoveCd:0, atkCd:0, stanceCd:0, exhaust:0, blockFlash:0, hurtFlash:0,
  },o);
}
const FOES={
  brigand:{name:'林中盗匪', epithet:'亡命之徒', color:0x4a4a38, plume:0x333326, dmg:20, resolveMax:80,
    windup:470, reaction:520, reactP:.35, aggr:1.15, feintP:.05, counter:false, speed:150,
    stanceW:[0.35,0.4,0.25],
    habit:'出手毫无章法，却下手极狠。'},
  talbot:{name:'塔尔博', epithet:'红野猪', color:0x8E3B2E, plume:0x6b1f14, dmg:22, resolveMax:100,
    windup:520, reaction:700, reactP:.28, aggr:1.25, feintP:.04, counter:false, speed:165,
    stanceW:[0.62,0.25,0.13],
    habit:'出手必是大开大合的上段劈砍，格挡却慢。举剑时看他的肩。'},   /* 步战之言，马上另有一句 */
  edmund:{name:'埃德蒙爵士', epithet:'灰鹭', color:0x5A6A76, plume:0xB9C4CC, dmg:22, resolveMax:105,
    windup:430, reaction:230, reactP:.85, aggr:.45, feintP:.10, counter:true, speed:140,
    stanceW:[0.3,0.4,0.3],
    habit:'从不先动手。他盯着你的起手式格挡，格开便还击。唯有出剑途中变势的虚招能骗过他。'},
  belloc:{name:'贝洛克男爵', epithet:'黑塔', color:0x24202A, plume:0x101014, dmg:24, resolveMax:120,
    windup:390, reaction:280, reactP:.72, aggr:.95, feintP:.38, counter:true, speed:170,
    stanceW:[0.33,0.34,0.33],
    habit:'他自己就惯用虚招，且专挑你力竭时抢攻。稳住体势，后发制人。'},
};
function startDuel(foeId,opts){
  const cfg=FOES[foeId];
  const intel=G.flags['intel_'+foeId];
  duel={
    cfg:Object.assign({},cfg), opts, foeId,
    p:mkFighter({x:290,face:1}),
    e:mkFighter({x:670,face:-1,resolve:cfg.resolveMax,resolveMax:cfg.resolveMax}),
    phase:'salute', phaseT:3.4, saluted:false,
    intel, over:false, aiThink:0, aiReactT:-1, eMove:0, eJustBlocked:false,
  };
  if(opts.pHandicap) duel.p.resolve=100-opts.pHandicap;
  setFoeActor(foeId);
  if(P_ACT) P_ACT.root.visible=true;
  if(E_ACT) E_ACT.root.visible=true;
  G.scene='duel'; hud();
  duelHudShow(`${cfg.name} <small>${cfg.epithet}</small>`);
  $('#roundname').textContent=opts.roundName||'';
  hint('A/D 或 ←→ 移动 · W/S 或 ↑↓ 换势 · J/空格 出剑 · K 撞盾 · 出剑途中换势即是虚招');
  banner(opts.title||'决斗',1500);
  if(intel) setTimeout(()=>caption('老侍从之言：'+cfg.habit,5200),1600);
  sfx.horn();
}
function fTick(f,dt){
  f.t-=dt; f.shoveCd-=dt; f.atkCd-=dt; f.stanceCd-=dt;
  f.blockFlash-=dt; f.hurtFlash-=dt;
  if(f.exhaust>0){ f.exhaust-=dt; }
  else f.stam=clamp(f.stam+(f.state==='idle'?16:8)*dt,0,100);
}
function tryAttack(f){
  if(f.state!=='idle'||f.atkCd>0||f.exhaust>0) return false;
  if(f.stam<24) return false;
  f.stam-=24; f.state='windup'; f.strikeStance=f.stance; f.feinted=false;
  f.t=(f===duel.p?0.36:(duel.cfg.windup+(duel.intel&&f===duel.e?140:0))/1000);
  return true;
}
function tryShove(f,g){
  if(f.state!=='idle'||f.shoveCd>0||f.exhaust>0||f.stam<20) return;
  f.shoveCd=0.9; f.stam-=20;
  if(Math.abs(f.x-g.x)<105 && g.state!=='stagger'){
    if(g.state==='windup'||g.state==='idle'){
      g.state='stagger'; g.t=0.68; sfx.shove(); shake=Math.max(shake,.25);
      caption2('撞盾！'+(g===duel.e?'对手趔趄了':'你被撞得趔趄'));
    }
  }else sfx.swing();
}
function setStance(f,dir){
  if(f.stanceCd>0||f.exhaust>0) return;
  const ns=clamp(f.stance+dir,0,2);
  if(ns===f.stance) return;
  f.stance=ns; f.stanceCd=0.09;
  if(f.state==='windup'){
    if(f.stam>=8){ f.stam-=8; f.strikeStance=f.stance; f.feinted=true; }
    else f.stance=f.strikeStance;
  }
}
function midPos(){
  return new THREE.Vector3(((duel.p.x+duel.e.x)/2-480)*S,1.35,0.15);
}
function resolveStrike(att,def,isPlayerAtt){
  const gap=Math.abs(att.x-def.x);
  att.state='strike'; att.t=0.09; sfx.swing();
  if(gap>140){ return; }
  const canBlock=(def.state==='idle'||def.state==='windup') && def.exhaust<=0 && def.state!=='stagger';
  if(canBlock && def.stance===att.strikeStance){
    def.stam=clamp(def.stam-10,0,100); def.blockFlash=0.3; def._blockPulse=true; sfx.clang();
    spawnSparks(midPos(),0xFFD873); shake=Math.max(shake,.2);
    att.state='recover'; att.t=0.46; att.atkCd=0.5;
    if(isPlayerAtt) duel.eJustBlocked=true;
    return;
  }
  const dmg=isPlayerAtt?22:duel.cfg.dmg;
  def.resolve-=dmg; def.hurtFlash=0.35; def._hitPulse=true; sfx.hit();
  spawnSparks(midPos(),0xFF7A4A); shake=Math.max(shake,.4);
  def.x=clamp(def.x+(def.x>att.x?26:-26),80,880);
  att.state='recover'; att.t=0.3; att.atkCd=0.34;
  if(def.state==='windup') def.state='idle';
  if(def.resolve<=0){
    def.resolve=0;
    if(def===duel.e){ def.state='yield'; duel.over=true; sfx.yield_(); setTimeout(()=>duel&&duel.opts.onWin(),1100); }
    else { duel.over=true; setTimeout(()=>duelLost(),800); }
  }
}
function tickDuel(dt){
  const d=duel; if(!d) return;
  const p=d.p, e=d.e;
  if(d.phase==='salute'){
    d.phaseT-=dt;
    p.phaseSalute=d.saluted;
    $('#salutetip').style.display='block';
    $('#salutetip').textContent=d.saluted?'礼毕 · 开赛于 '+Math.ceil(d.phaseT)+'…':'按 K 向对手行礼（也可不行） · '+Math.ceil(d.phaseT);
    if((pressed.KeyK||pressed.KeyB) && !d.saluted){
      d.saluted=true; G.v.li++;
      const resp={brigand:'盗匪愣了一下，随即狞笑。',
        talbot:'塔尔博啐了一口，没有还礼。',
        edmund:'埃德蒙爵士郑重举剑还礼。',
        belloc:G.flags.baronGrudge?'贝洛克冷冷道："沙溪村的多事骑士。"草草还了半礼。':'贝洛克微一颔首，还礼。'}[d.foeId];
      caption(resp,3000);
      if(d.foeId==='edmund') e.phaseSalute=true;
      deed_once('salute','临阵向对手行礼，不失骑士之仪');
    }
    if(d.phaseT<=0){
      d.phase='fight'; p.phaseSalute=false; e.phaseSalute=false;
      $('#salutetip').style.display='none';
      banner('比武开始',1000);
    }
    return;
  }
  if(d.over){ fTick(p,dt); fTick(e,dt); return; }
  fTick(p,dt); fTick(e,dt);
  p.vx=0;
  if(p.state==='idle'&&p.exhaust<=0){
    let mv=0;
    if(keys.ArrowLeft||keys.KeyA) mv-=1;
    if(keys.ArrowRight||keys.KeyD) mv+=1;
    if(mv){ p.x=clamp(p.x+mv*170*dt,80,e.x-80); p.vx=mv*170; }
  }
  if(pressed.ArrowUp||pressed.KeyW) setStance(p,-1);
  if(pressed.ArrowDown||pressed.KeyS) setStance(p,1);
  if(pressed.KeyJ||pressed.Space) tryAttack(p);
  if(pressed.KeyK||pressed.KeyB) tryShove(p,e);
  if(p.stam<=0&&p.exhaust<=0&&p.state==='idle'){ p.exhaust=1.35; caption2('你力竭了——喘口气！'); }
  if(p.state==='windup'&&p.t<=0) resolveStrike(p,e,true);
  else if(p.state==='strike'&&p.t<=0) p.state='recover';
  else if(p.state==='recover'&&p.t<=0) p.state='idle';
  if(p.state==='stagger'&&p.t<=0) p.state='idle';
  aiTick(dt); aiMove(dt);
  if(e.state==='windup'&&e.t<=0) resolveStrike(e,p,false);
  else if(e.state==='strike'&&e.t<=0) e.state='recover';
  else if(e.state==='recover'&&e.t<=0) e.state='idle';
  if(e.state==='stagger'&&e.t<=0) e.state='idle';
  if(e.stam<=0&&e.exhaust<=0&&e.state==='idle') e.exhaust=1.35;
}
function aiTick(dt){
  const d=duel, cfg=d.cfg, e=d.e, p=d.p;
  const gap=Math.abs(e.x-p.x);
  if(p.state==='windup'){
    if(d.aiReactT<0) d.aiReactT=cfg.reaction/1000;
    if(d.aiReactT<900){
      d.aiReactT-=dt;
      if(d.aiReactT<=0){
        if(e.state==='idle' && Math.random()<cfg.reactP) e.stance=p.stance;
        d.aiReactT=999;
      }
    }
  } else d.aiReactT=-1;
  if(d.eJustBlocked && cfg.counter && e.state==='idle'){
    d.eJustBlocked=false;
    if(e.stam>30){ tryAttack(e); return; }
  }
  d.aiThink-=dt;
  if(e.state==='windup'){
    if(!e.feinted && e.t<cfg.windup/2000 && Math.random()<cfg.feintP){
      const ns=[0,1,2].filter(s=>s!==e.stance)[Math.random()<0.5?0:1];
      e.stance=ns; e.strikeStance=ns; e.feinted=true;
    }
    return;
  }
  if(e.state!=='idle'||e.exhaust>0) return;
  if(d.aiThink>0) return;
  d.aiThink=0.12+Math.random()*0.18;
  const wantGap=120;
  const punish=d.foeId==='belloc'&&p.exhaust>0;
  const aggr=cfg.aggr*(punish?2.2:1);
  if(gap>wantGap+18){ d.eMove=-1; }
  else if(gap<70 && Math.random()<0.4){ d.eMove=1; }
  else if(e.stam>(cfg.counter?46:30) && Math.random()<0.22*aggr){ d.eMove=0;
    const r=Math.random(), w=cfg.stanceW;
    e.stance=r<w[0]?0:(r<w[0]+w[1]?1:2);
    tryAttack(e);
  } else if(Math.random()<0.25 && gap<90 && p.blockFlash<=0 && e.stam>40 && Math.random()<0.3){
    d.eMove=0; tryShove(e,p);
  } else if(Math.random()<0.3){
    d.eMove=0;
    e.stance=clamp(e.stance+(Math.random()<0.5?-1:1),0,2);
  } else d.eMove=0;
}
function aiMove(dt){
  const d=duel, e=d.e, p=d.p;
  e.vx=0;
  if(!d.eMove||e.state!=='idle'||e.exhaust>0) return;
  const nx=clamp(e.x+d.eMove*d.cfg.speed*dt*(d.eMove<0?1:0.8), p.x+80, 880);
  e.vx=(nx-e.x)/Math.max(dt,1e-4); e.x=nx;
}
function duelLost(){
  const d=duel;
  showPanel({
    title:'败阵', body:[d.opts.loseText||'你的气势散了，剑尖垂了下去。司仪唱名：对手得胜。'],
    choices:[{label:'再战一场', sub:'胜负乃常事，可雪耻不可怯阵。', fx:()=>{
      startDuel(d.foeId, d.opts);
    }}],
  });
}
function endDuelToMap(){
  duel=null; duelHudHide();
  G.scene='map'; hud(); hint(MAP_HINT);
}

/* ================= 马上长枪对冲 ================= */
const ZONE_Y={helm:2.1, chest:1.8, shield:1.5};
const ZONE_PTS={helm:3, chest:2, shield:1};
const ZONE_NAME={helm:'盔',chest:'胸',shield:'盾'};
const AIM_MIN=1.35, AIM_MAX=2.35;
const JOUST_AI={
  talbot:{zoneW:{helm:.1,chest:.72,shield:.18}, acc:.1, brace:[.5,.72], guard:.35, speed:5.2,
    jhabit:'马上一枪永远瞄你的胸甲，夹枪又总是过早——冲到半程枪尖就压下来了。'},
  belloc:{zoneW:{helm:.42,chest:.42,shield:.16}, acc:.055, brace:[.78,.96], guard:.72, speed:5.5,
    jhabit:'马上他惯打盔顶，枪快而准，极难挑落。护住自己，赌一枪正的。'},
};
let joust=null, JW=null;
function buildLance(bandHex){
  const g=new THREE.Group();
  const shaft=new THREE.Mesh(new THREE.CylinderGeometry(.026,.052,3.3,8),M.wood);
  shaft.rotation.z=-Math.PI/2; shaft.position.x=1.55; shaft.castShadow=true; g.add(shaft);
  const band=new THREE.Mesh(new THREE.CylinderGeometry(.056,.056,.25,8),
    new THREE.MeshStandardMaterial({color:bandHex,roughness:.6,metalness:.3}));
  band.rotation.z=-Math.PI/2; band.position.x=.9; g.add(band);
  const guard=new THREE.Mesh(new THREE.ConeGeometry(.16,.22,10),M.armorDark);
  guard.rotation.z=Math.PI/2; guard.position.x=.42; g.add(guard);
  const tip=new THREE.Mesh(new THREE.ConeGeometry(.035,.16,8),M.blade);
  tip.rotation.z=-Math.PI/2; tip.position.x=3.28; g.add(tip);
  return g;
}
function ensureJoustWorld(){
  if(JW) return;
  const barrier=new THREE.Group();
  const rail=new THREE.Mesh(new THREE.BoxGeometry(15,.8,.12),M.wood);
  rail.position.y=.5; rail.castShadow=true; barrier.add(rail);
  const cloth=new THREE.Mesh(new THREE.BoxGeometry(15,.34,.2),
    new THREE.MeshStandardMaterial({color:0x8E2B20,roughness:.85}));
  cloth.position.y=1.0; cloth.castShadow=true; barrier.add(cloth);
  for(let x=-7;x<=7;x+=2){
    const post=new THREE.Mesh(new THREE.CylinderGeometry(.06,.06,1.1,7),M.woodDark);
    post.position.set(x,.55,0); barrier.add(post);
  }
  duelScene.add(barrier);
  const hp=buildHorse(0x5c452c), he=buildHorse(0x35302c);
  hp.riderOld.visible=false; he.riderOld.visible=false;
  he.root.rotation.y=Math.PI;
  duelScene.add(hp.root); duelScene.add(he.root);
  const lp=buildLance(0xC9A227), le=buildLance(0x7a7a7a);
  lp.position.set(.15,1.7,.24); lp.rotation.y=0.16; hp.root.add(lp);
  const le2=le; le2.position.set(.15,1.7,.24); le2.rotation.y=0.16; he.root.add(le2);
  JW={barrier,hp,he,lp,le,pRider:null,eRider:null};
  setJoustVisible(false);
}
function setJoustVisible(v){
  JW.barrier.visible=v; JW.hp.root.visible=v; JW.he.root.visible=v;
}
function clearJoustRiders(){
  for(const k of ['pRider','eRider']){
    const r=JW[k];
    if(r){ r.root.parent&&r.root.parent.remove(r.root); JW[k]=null; }
  }
}
function joustRiders(foeId){
  clearJoustRiders();
  const mk=(model,style)=>{
    const a=new Actor(model,Object.assign({scale:0.82},style));
    a.play('Sit_Chair_Idle');
    a.root.rotation.y=Math.PI/2;
    a.root.position.set(-.02,1.22,0);
    return a;
  };
  JW.pRider=mk('knight',{show:['1H_Sword','Badge_Shield','Knight_Helmet','Knight_Cape']});
  JW.hp.root.add(JW.pRider.root);
  const st=FOE_STYLE[foeId]||FOE_STYLE.belloc;
  JW.eRider=mk(st.model,{show:st.show,tint:st.tint});
  JW.he.root.add(JW.eRider.root);
}
function startJoust(foeId,opts){
  ensureJoustWorld(); joustRiders(foeId);
  setJoustVisible(true);
  if(P_ACT) P_ACT.root.visible=false;      /* 步战演员让场 */
  if(E_ACT) E_ACT.root.visible=false;
  joust={
    foeId, opts, cfg:JOUST_AI[foeId],
    pass:1, passes:opts.passes||3, pts:{p:0,e:0}, qSum:{p:0,e:0},
    phase:'ready', t:0, slow:1, fall:null,
    px:-7.2, ex:7.2, vp:0, ve:0,
    aim:1.8, wob:0, wobT:0, braced:false, braceQ:0, early:false,
    eZone:null, eBraceQ:0,
    lastPass:null, decided:null, gallopT:0,
  };
  pickFoePassPlan();
  G.scene='joust'; hud(); duelHudHide();
  $('#jgauge').style.display='block'; $('#jgauge').classList.remove('braced');
  $('#roundname').textContent=opts.roundName||'马上长枪';
  hint('W/S 调整枪尖高低 · 冲近一瞬按 J 夹枪锁定 · 盾一分 胸两分 盔三分 · 坠马立判');
  banner('第 '+'一二三四五'[joust.pass-1]+' 合',1400);
  if(G.flags['intel_'+foeId]&&joust.cfg.jhabit) setTimeout(()=>caption('老侍从之言：'+joust.cfg.jhabit,5200),1500);
  sfx.horn();
}
function pickFoePassPlan(){
  const j=joust, w=j.cfg.zoneW, r=Math.random();
  j.eZone=r<w.helm?'helm':(r<w.helm+w.chest?'chest':'shield');
  j.eBraceQ=j.cfg.brace[0]+Math.random()*(j.cfg.brace[1]-j.cfg.brace[0]);
  j.braced=false; j.early=false; j.braceQ=0; j.wobT=Math.random()*9;
}
const gauss=()=>((Math.random()+Math.random()+Math.random())-1.5);
function resolvePass(){
  const j=joust;
  /* 玩家判定 */
  let pRes=null;
  const effAim=j.aim+j.wob;
  if(j.braced){
    let zone=null,best=1;
    for(const z of Object.keys(ZONE_Y)){
      const e=Math.abs(effAim-ZONE_Y[z]);
      if(e<0.14&&e<best){ zone=z; best=e; }
    }
    if(zone) pRes={zone, q:ZONE_PTS[zone]*j.braceQ*(1-best*2.2)};
  }
  /* 对手判定 */
  let eRes=null;
  {
    const err=Math.abs(gauss()*j.cfg.acc*2);
    if(err<0.14) eRes={zone:j.eZone, q:ZONE_PTS[j.eZone]*j.eBraceQ*(1-err*2.2)};
  }
  if(pRes){ j.pts.p+=ZONE_PTS[pRes.zone]; j.qSum.p+=pRes.q; }
  if(eRes){ j.pts.e+=ZONE_PTS[eRes.zone]; j.qSum.e+=eRes.q; }
  const pq=pRes?pRes.q:0, eq=eRes?eRes.q:0;
  let unhorse=null;
  if(pq>=1.85&&pq-eq>0.85&&Math.random()<(pq-1.5)*0.38+(1-j.cfg.guard)*0.3) unhorse='e';
  else if(eq>=1.85&&eq-pq>0.85&&Math.random()<(eq-1.5)*0.26) unhorse='p';
  j.lastPass={pRes,eRes,unhorse};
  /* 演出 */
  const midX=(j.px+j.ex)/2;
  if(pRes){ spawnSparks(new THREE.Vector3(midX+.5,ZONE_Y[pRes.zone],-.4),0xFFD873); }
  if(eRes){ spawnSparks(new THREE.Vector3(midX-.5,ZONE_Y[eRes.zone],.4),0xFF7A4A); }
  if(pRes||eRes){ sfx.crack(); shake=Math.max(shake,.7); j.slow=0.22; }
  else sfx.swing();
  if(unhorse){
    banner('坠　马！',2000); startFall(unhorse);
    if(unhorse==='e') sfx.cheer(1.2); else sfx.gasp();
  }
  else if(pRes) banner('中'+ZONE_NAME[pRes.zone]+'！'+'　一二三'[ZONE_PTS[pRes.zone]]+' 分',1500);
  else banner('枪走空了',1200);
  const en=FOES[j.foeId].name;
  setTimeout(()=>{ if(joust) caption(
    (j.lastPass.eRes?en+'的枪中了你的'+ZONE_NAME[j.lastPass.eRes.zone]+'甲。':en+'的枪擦身而过。')+
    '　战况 '+j.pts.p+' — '+j.pts.e,3400); },1600);
}
function startFall(who){
  const j=joust;
  const rider=who==='e'?JW.eRider:JW.pRider;
  duelScene.attach(rider.root);
  j.fall={who, rider, vy:2.6, vx:(who==='e'?1:-1)*2.2, landed:false};
  rider.play('Hit_B',{loop:false,clamp:true});
}
function finishJoust(){
  const j=joust;
  let winner=null, unhorse=j.decided&&j.decided.unhorse||null;
  if(unhorse) winner=unhorse==='e'?'p':'e';
  else if(j.pts.p!==j.pts.e) winner=j.pts.p>j.pts.e?'p':'e';
  else if(Math.abs(j.qSum.p-j.qSum.e)>0.01) winner=j.qSum.p>j.qSum.e?'p':'e';
  const result={winner, unhorse, pts:{...j.pts}};
  setJoustVisible(false);
  clearJoustRiders();
  $('#jgauge').style.display='none';
  $('#roundname').textContent='';
  joust=null;
  G.scene='duel';           /* 竞技场空景垫底，等待面板/下一阶段 */
  j.opts.onDone(result);
}
function tickJoust(dt){
  const j=joust; if(!j) return;
  j.slow+=(1-j.slow)*lerpK(dt,2.2);
  const sdt=dt*j.slow;
  j.t+=sdt;
  /* 落马动画 */
  if(j.fall&&!j.fall.landed){
    const f=j.fall, r=f.rider.root;
    f.vy-=9.2*sdt;
    r.position.y+=f.vy*sdt; r.position.x+=f.vx*sdt;
    r.rotation.z+=(f.who==='e'?1:-1)*2.2*sdt;
    if(r.position.y<=0.12){
      r.position.y=0.12; f.landed=true;
      f.rider.play('Sit_Floor_Down',{loop:false,clamp:true});
      r.rotation.z*=0.3;
    }
  }
  switch(j.phase){
    case 'ready':
      if(j.t>1.5){ j.phase='charge'; j.t=0; banner('冲　！',800); }
      break;
    case 'charge':{
      j.vp=Math.min(j.vp+2.6*sdt,5.2);
      j.ve=Math.min(j.ve+2.6*sdt,j.cfg.speed);
      j.px+=j.vp*sdt; j.ex-=j.ve*sdt;
      j.gallopT-=sdt;
      if(j.gallopT<=0){ j.gallopT=0.21; sfx.hoof(); }
      /* 瞄准 */
      let da=0;
      if(keys.KeyW||keys.ArrowUp) da+=1;
      if(keys.KeyS||keys.ArrowDown) da-=1;
      j.aim=clamp(j.aim+da*1.05*sdt,AIM_MIN,AIM_MAX);
      j.wobT+=sdt;
      const amp=(0.028+j.vp*0.02)*(j.braced?0.32:1)*(j.early?1.7:1);
      j.wob=Math.sin(j.wobT*8.7)*amp+Math.sin(j.wobT*5.1+1.3)*amp*0.6;
      /* 夹枪 */
      const gap=j.ex-j.px, closing=j.vp+j.ve, tti=gap/Math.max(closing,0.1);
      if((pressed.KeyJ||pressed.Space)&&!j.braced){
        j.braced=true;
        $('#jgauge').classList.add('braced');
        if(tti>2.1){ j.braceQ=0.35; j.early=true; caption2('夹枪太早——手臂在发颤！'); }
        else{
          j.braceQ=1-Math.min(Math.abs(tti-0.75)/0.9,0.65);
          caption2(j.braceQ>0.85?'夹得正！':'枪已夹定');
        }
        sfx.brace(j.braceQ);
      }
      if(gap<=1.15){ j.phase='impact'; j.t=0; resolvePass(); }
      break;
    }
    case 'impact':
      j.px+=j.vp*sdt; j.ex-=j.ve*sdt;
      j.vp=Math.max(0,j.vp-3.5*sdt); j.ve=Math.max(0,j.ve-3.5*sdt);
      j.px=Math.min(j.px,7.4); j.ex=Math.max(j.ex,-7.4);
      if(j.t>2.0){
        const lp=j.lastPass;
        const singleDone=j.passes===1;
        const decided=lp.unhorse||singleDone||
          (j.pass>=j.passes&&j.pts.p!==j.pts.e)||(j.pass>=5);
        if(decided){ j.decided=lp; j.phase='result'; j.t=0; }
        else{ j.phase='turn'; j.t=0; $('#fade').style.opacity=1; }
      }
      break;
    case 'turn':
      if(j.t>0.5){
        j.pass++;
        j.px=-7.2; j.ex=7.2; j.vp=0; j.ve=0;
        j.aim=1.8; pickFoePassPlan();
        $('#jgauge').classList.remove('braced');
        $('#fade').style.opacity=0;
        j.phase='ready'; j.t=0;
        banner('第 '+'一二三四五'[Math.min(j.pass-1,4)]+' 合',1400);
      }
      break;
    case 'result':
      if(j.t>2.2) finishJoust();
      break;
  }
  /* 测试钩子 */
  if(j._force){
    j.pts=j._force==='p'?{p:9,e:0}:{p:0,e:9};
    j.decided=null; j.lastPass=j.lastPass||{pRes:null,eRes:null,unhorse:null};
    j._force=null; j.phase='result'; j.t=99;
  }
}
function renderJoust(dt,t){
  const j=joust; if(!j) return;
  const sdt=dt*j.slow;
  /* 马匹与骑手 */
  JW.hp.root.position.set(j.px,0,0.55);
  JW.he.root.position.set(j.ex,0,-0.55);
  const gaitP=j.vp>0.2?1:0, gaitE=j.ve>0.2?1:0;
  JW.hp.legs.forEach((g,i)=>{ g.rotation.z=gaitP*Math.sin(t*13+(i%2?Math.PI:0)+(i>1?1.4:0))*0.6; });
  JW.he.legs.forEach((g,i)=>{ g.rotation.z=gaitE*Math.sin(t*13+(i%2?Math.PI:0)+(i>1?1.4:0))*0.6; });
  JW.hp.root.position.y=gaitP*Math.abs(Math.sin(t*13))*0.06;
  JW.he.root.position.y=gaitE*Math.abs(Math.sin(t*13))*0.06;
  if(JW.pRider) JW.pRider.mixer.update(sdt);
  if(JW.eRider) JW.eRider.mixer.update(sdt);
  /* 长枪姿态：未夹枪斜举，夹枪后放平指向瞄准高度 */
  const couch=j.braced||j.phase!=='charge';
  const pTilt=j.braced?((j.aim+j.wob)-1.7)/3.0:0.95-(j.vp*0.06);
  JW.lp.rotation.z+=(pTilt-JW.lp.rotation.z)*lerpK(dt,j.braced?10:4);
  const eTilt=(j.phase==='charge'&&(j.ex-j.px)/(j.vp+j.ve+0.1)<1.4)?((ZONE_Y[j.eZone]||1.8)-1.7)/3.0:0.95-(j.ve*0.06);
  JW.le.rotation.z+=(eTilt-JW.le.rotation.z)*lerpK(dt,6);
  /* 瞄准标尺 */
  const mark=$('#jmark');
  if(mark) mark.style.top=((AIM_MAX-(j.aim+j.wob))/(AIM_MAX-AIM_MIN)*100)+'%';
  /* 旗与粒子 */
  duelScene.userData.flags.forEach((f,i)=>{ f.rotation.y=Math.sin(t*1.8+i)*0.25; });
  tickSparks(sdt);
  /* 相机 */
  const mid=(j.px+j.ex)/2;
  let cx,cy,cz,lx,ly;
  if(j.phase==='ready'){ cx=j.px+2.4; cy=1.45; cz=5.6; lx=j.px+4; ly=1.7; }
  else if(j.phase==='charge'){ cx=mid*0.72; cy=1.75; cz=6.4-Math.min(j.vp,5)*0.28; lx=mid; ly=1.55; }
  else if(j.phase==='impact'){ cx=mid; cy=1.5; cz=3.9; lx=mid; ly=1.6; }
  else{ /* result/turn：环视 */
    const a=t*0.35;
    const fx=j.fall?j.fall.rider.root.position.x:mid;
    cx=fx+Math.sin(a)*4.2; cy=1.6; cz=Math.cos(a)*4.2; lx=fx; ly=1.0;
  }
  camTmp.set(cx,cy,cz);
  camera.position.lerp(camTmp,lerpK(dt,3.2));
  shake=Math.max(0,shake-dt*1.6);
  if(shake>0){
    camera.position.x+=(Math.random()-.5)*shake*.2;
    camera.position.y+=(Math.random()-.5)*shake*.15;
  }
  const wantFov=baseFov-shake*8;
  if(Math.abs(camera.fov-wantFov)>0.05){ camera.fov+=(wantFov-camera.fov)*lerpK(dt,10); camera.updateProjectionMatrix(); }
  lookTmp.set(lx,ly,0);
  camera.lookAt(lookTmp);
  renderer.render(duelScene,camera);
}
function joustLost(foeId,opts,r){
  showPanel({
    title:'败阵',
    body:[r.unhorse==='p'?'长枪正中你的胸甲，你腾空离鞍，重重摔在栅栏边。侍从跑来扶你，满耳只有嗡嗡的风。':
      '三合已毕，司仪的旗指向对面。你的枪不够正，也不够稳。'],
    choices:[{label:'再战一场', sub:'胜负乃常事，可雪耻不可怯阵。', fx:()=>startJoust(foeId,opts)}],
  });
}

/* ================= 事件（文案与 2D 版一致） ================= */
const EVENTS={
  village(){
    showPanel({
      title:'沙溪村',
      body:['村口围着一圈人。男爵的税吏攥着一头黄牛的缰绳，牛主人是个寡妇，两个孩子抓着她的裙角。',
        '税吏晃着税册："欠租<em>三枚银币</em>，牛抵债，天经地义。"'],
      choices:[
        {label:'替她付清三枚银币', sub:'解今日之困。（钱袋 −3）', disabled:G.coins<3, fx:()=>{
          G.coins-=3; G.v.ren++; G.v.yi++; sfx.coin();
          deed('倾囊三银，为寡妇解税吏之厄');
          villageOath();
        }},
        {label:'按剑上前，喝止税吏', sub:'牛可以留下，梁子也就结下了。', fx:()=>{
          G.v.yi++; G.flags.baronGrudge=true;
          deed('仗剑喝退税吏，护住孤儿寡母');
          showPanel({title:'沙溪村',
            body:['税吏松了缰绳，退开几步，眼睛却盯着你盾上的纹章记了又记。',
              '"好，好。<em>贝洛克男爵</em>的地界上，轮到过路骑士说话了。"他冷笑着走了。'],
            choices:[{label:'……', fx:villageOath}]});
        }},
        {label:'拨马绕行', sub:'路还长，事非己事。', fx:()=>{
          G.v.yi--; deed('过沙溪村，见孤寡受迫而不顾');
          caption('身后的哭声隔着风，跟了你一里地。',3600);
        }},
      ],
    });
  },
  forest(){
    showPanel({
      title:'黑桦林',
      body:['林子深处传来呼救——"救命——"，喊声却在半途<em>戛然而止</em>，像被人掐断。'],
      choices:[
        {label:'下马，绕行林缘，先察看动静', sub:'救人以义，行之以智。', fx:()=>{
          G.v.zhi++;
          showPanel({title:'黑桦林',
            body:['你伏在高坡的蕨丛后望下去：两名盗匪伏在倒木之后，方才"呼救"的正是其中之一。',
              '倒木旁横着一具行商的尸首——这陷阱，已经害过人了。'],
            choices:[
              {label:'出其不意，居高喝令弃械', sub:'先声夺人，占尽先手。', fx:()=>{
                deed('识破林中假呼救之伏');
                startDuel('brigand',{title:'林中缠斗', roundName:'黑桦林 · 真剑',
                  loseText:'盗匪的刀比想象中沉。你且退且战，脱出了林子——此路不通。',
                  onWin:brigandYield});
                duel.e.stam=55;
              }},
              {label:'悄然退开，绕林而行', sub:'不入危墙之下。', fx:()=>{
                deed('识破埋伏，绕林而过');
                caption('你在林缘立了一块斜木，刻上"内有伏莽"四字。',3800);
              }},
            ]});
        }},
        {label:'纵马直入林中', sub:'救人如救火。', fx:()=>{
          deed('闻呼救而直入黑桦林');
          showPanel({title:'黑桦林',
            body:['箭从倒木后射出，擦开你的肩甲——是<em>伏兵</em>。一名盗匪提刀跃出。'],
            choices:[{label:'拔剑！', fx:()=>{
              startDuel('brigand',{title:'林中遇伏', roundName:'黑桦林 · 真剑', pHandicap:20,
                loseText:'盗匪的刀比想象中沉。你且退且战，脱出了林子——此路不通。',
                onWin:brigandYield});
            }}]});
        }},
      ],
    });
  },
  ford(){
    showPanel({
      title:'苇渡口',
      body:['渡口无人。芦苇丛里躺着一名信使——坠马而亡，看装束已有些时日。',
        '行囊里有<em>五枚银币</em>，和一封火漆未拆的信，收信人是比武大会的司仪官。',
        '四下无人。唯有流水。'],
      choices:[
        {label:'收殓遗体，银币与信一并带往大会交还', sub:'', fx:()=>{
          G.v.shendu+=2; G.flags.courierLetter=true;
          G.hiddenDeeds.push('渡口无人处，收殓信使，分文未取');
          if(mapScene.userData.courier) mapScene.userData.courier.visible=false;
          caption('你堆石为坟。水声不停。',3600);
        }},
        {label:'取走银币，信留在原处', sub:'（钱袋 +5）', fx:()=>{
          G.coins+=5; G.v.shendu-=2; G.flags.tookPurse=true; sfx.coin();
          G.hiddenDeeds.push('渡口无人处，取亡者之财');
          caption('银币入袋，没有一点声音。',3600);
        }},
        {label:'不动分毫，策马离开', sub:'', fx:()=>{
          caption('芦苇合拢，像什么都没发生过。',3600);
        }},
      ],
    });
  },
  field(){ tourneyEntry(); },
};
function villageOath(){
  showPanel({
    title:'寡妇之请',
    body:['寡妇拉着两个孩子跪谢。起身时她忽然道：',
      '"骑士老爷——大会上诸侯齐聚，<em>贝洛克男爵</em>也在。能否替沙溪村进一言，减免今年秋租？满村的收成，撑不到冬天了。"'],
    quiet:'一诺既出，便入誓约簿。',
    choices:[
      {label:'立誓：大会之上，必为沙溪村陈情', sub:'君子重然诺。', fx:()=>{
        G.oaths.push({text:'为沙溪村向男爵陈情减租', kept:null});
        caption('她记住了你盾上的纹章。',3200);
      }},
      {label:'不敢应承："此事我未必做得到。"', sub:'不轻诺，故寡悔。', fx:()=>{
        G.v.zhi++; deed('不轻然诺，如实相告');
      }},
    ],
  });
}
function brigandYield(){
  showPanel({
    title:'剑下之人',
    body:['盗匪的刀脱了手，人跪在腐叶里，粗声喘气："要杀要剐，痛快些。"',
      '这里是荒林深处。律法已死，无人来断他的罪。'],
    choices:[
      {label:'收缴兵刃，放他去', sub:'"再让我见你劫道，不饶。"', fx:()=>{
        G.v.ren++; deed('林中胜而不杀，缴械纵之');
        showPanel({title:'剑下之人',
          body:['盗匪愣了半晌，抓起同伴逃了。跑出十几步，他回头看了你一眼——那眼神不是怕。'],
          choices:[{label:'继续赶路', fx:endDuelToMap}]});
      }},
      {label:'索要盘缠，再放他去', sub:'（钱袋 +2）', fx:()=>{
        G.coins+=2; sfx.coin(); deed('胜盗匪，取盘缠而纵之');
        endDuelToMap();
      }},
      {label:'取他性命', sub:'荒林无人知。', fx:()=>{
        stain('杀降'); G.v.ren-=2; G.v.shendu--;
        G.hiddenDeeds.push('荒林无人处，杀已降之人');
        caption('林子静得很。只有你自己听见了那一声。',4000);
        endDuelToMap();
      }},
    ],
  });
}
/* ================= 比武大会 ================= */
function tourneyEntry(){
  const fee=2;
  const entries=[
    {label:`报名参赛（报名银 ${fee} 枚）`, sub:'亮出纹章，录入名册。', disabled:G.coins<fee, fx:()=>{
      G.coins-=fee; sfx.coin(); afterEntry();
    }},
  ];
  if(G.coins<fee) entries.push({label:'典当马鞍换二银，再行报名', sub:'鞍可再置，会不再来。', fx:()=>{
    G.flags.saddlePawned=true; G.coins+=2-fee; deed('典鞍赴会'); afterEntry();
  }});
  showPanel({
    title:'圣奥仑比武场',
    body:['场边旌旗猎猎，司仪官高踞木台唱名。比武依古礼用<em>钝剑</em>：胜负在气势，不在性命。',
      '规程三阵：胜者晋级，终阵对阵上届之主——<em>贝洛克男爵</em>。'],
    choices:entries,
  });
}
function afterEntry(){
  if(G.flags.courierLetter){
    showPanel({
      title:'呈上遗信',
      body:['你把银币与那封火漆信呈给司仪官，并说明渡口所见。',
        '司仪官拆信读罢，久久看你一眼："这是北境的<em>阵亡通知</em>。他家里人还在等信。"',
        '"没有赏金，骑士。多谢你。"'],
      choices:[{label:'"分内之事。"', fx:round1Intro}],
    });
  } else round1Intro();
}
function intelOffer(foeId,next){
  showPanel({
    title:'赛前 · 校场边',
    body:['下一阵的对手正在场边操练。一名白须老侍从倚着栅栏看，看得极精。',
      '"想听两句么，骑士？"他伸出一根手指，"一枚银币。"'],
    choices:[
      {label:'递上一枚银币，细细讨教', sub:'知彼知己。（钱袋 −1）', disabled:G.coins<1, fx:()=>{
        G.coins-=1; G.v.zhi++; G.flags['intel_'+foeId]=true; sfx.coin(); next();
      }},
      {label:'"不必了，场上见真章。"', sub:'', fx:next},
    ],
  });
}
function round1Intro(){
  intelOffer('talbot',()=>{
    showPanel({title:'第一阵 · 红野猪',
      body:['依大会规程，第一阵为<em>马上长枪</em>，三合定胜负：中盾一分，中胸两分，中盔三分——<em>坠马立判</em>。',
        '对面是<em>塔尔博</em>，诨号红野猪——三届大会靠蛮力打进过终阵的莽汉。他已跨在马上，长枪拄地，隔着栅栏冲你咧嘴。'],
      choices:[{label:'上马入场', fx:()=>{
        const opts={passes:3, roundName:'第一阵 · 马上长枪', onDone:r=>{
          if(r.winner==='p'){
            G.flags.talbotUnhorsed=r.unhorse==='e';
            tourneyYield('talbot',round2Intro);
          } else joustLost('talbot',opts,r);
        }};
        startJoust('talbot',opts);
      }}]});
  });
}
function round2Intro(){
  intelOffer('edmund',()=>{
    showPanel({title:'第二阵 · 灰鹭',
      body:['<em>埃德蒙爵士</em>年近六旬，甲叶擦得雪亮。人称灰鹭：不动如苇间之鹭，动则一击。',
        '他向观礼席行礼，一丝不苟。'],
      choices:[{label:'入场', fx:()=>{
        startDuel('edmund',{title:'第二阵', roundName:'第二阵 · 钝剑', onWin:()=>tourneyYield('edmund',finalIntro)});
      }}]});
  });
}
function finalIntro(){
  intelOffer('belloc',()=>{
    const grudge=G.flags.baronGrudge;
    showPanel({title:'终阵 · 黑塔',
      body:[(grudge?'<em>贝洛克男爵</em>缓步入场，目光在你盾上停了一停——他认得沙溪村那桩事。':
        '<em>贝洛克男爵</em>缓步入场，黑甲如塔，上届的桂冠还悬在他的帐前。'),
        '他忽然扬声，压过全场："钝剑是孩童的游戏。终阵，当用<em>利剑</em>——敢么？"',
        '满场霎时静了。司仪官皱眉看向你。'],
      choices:[
        {label:'应下利剑', sub:'生死各安天命。', fx:()=>{
          G.flags.sharpFinal=true; deed('终阵应利剑之约');
          bellocJoustThenSword({opts:{title:'终阵 · 利剑', roundName:'终阵 · 利剑', onWin:()=>tourneyYield('belloc',finale)}});
        }},
        {label:'请司仪依古礼断之', sub:'比武之礼，不为一人而改。', fx:()=>{
          G.v.li++; G.v.zhi++; deed('终阵守古礼，不逞血气');
          showPanel({title:'终阵 · 黑塔',
            body:['司仪官起身，一字一句："圣奥仑之会，行钝剑之礼，<em>百年未改</em>。"',
              '男爵冷笑一声接过钝剑。他的握法告诉你：他打算把钝剑抡出利剑的分量。'],
            choices:[{label:'入场', fx:()=>{
              bellocJoustThenSword({bluntBoost:true, opts:{title:'终阵', roundName:'终阵 · 钝剑', onWin:()=>tourneyYield('belloc',finale)}});
            }}]});
        }},
      ]});
  });
}
function bellocJoustThenSword(mods){
  showPanel({title:'终阵 · 先枪后剑',
    body:['依大会古例，终阵先行<em>马上一合</em>，再下马以剑决胜。马上的胜负不终结比试，却决定步战的先手气势。',
      '号角响了。贝洛克已在栅栏那头——黑马黑甲，枪尖不动如塔。'],
    choices:[{label:'上马', fx:()=>{
      startJoust('belloc',{passes:1, roundName:'终阵 · 马上一合', onDone:r=>{
        let pAdj=0,eAdj=0,flavor;
        if(r.unhorse==='e'){ eAdj=-55; deed('马上一合挑黑塔于马下');
          flavor='你的枪正得没有一丝偏差——<em>贝洛克被干净利落地挑下马来</em>。满场哗然：黑塔倒了。他起身时甲叶上全是土。步战于他，已是背水。'; }
        else if(r.unhorse==='p'){ pAdj=-30;
          flavor='他的枪快得看不清。你腾空离鞍，摔在土里，耳边全是嗡嗡的风。侍从扶你起身——剑还在，比试还没有完。'; }
        else if(r.winner==='p'){ eAdj=-25;
          flavor='两枪同时命中，你的更正。贝洛克下马时把断枪掷在地上——先手之势，在你。'; }
        else if(r.winner==='e'){ pAdj=-20;
          flavor='他的枪更快更准。你的胸甲凹了一块，喘息未定，便要步战。'; }
        else{ flavor='两枪俱空，不分高下。全场屏息，看你们各自下马，拔剑。'; }
        showPanel({title:'下马 · 拔剑', body:[flavor], choices:[{label:'步战开始', fx:()=>{
          startDuel('belloc', mods.opts);
          if(mods.bluntBoost){ duel.cfg.aggr*=1.3; duel.cfg.dmg=26; }
          duel.p.resolve=Math.max(20,100+pAdj);
          duel.e.resolve=Math.max(30,duel.e.resolveMax+eAdj);
        }}]});
      }});
    }}]});
}
function tourneyYield(foeId,next){
  const sharp=foeId==='belloc'&&G.flags.sharpFinal;
  const names={talbot:'塔尔博',edmund:'埃德蒙爵士',belloc:'贝洛克男爵'};
  const nm=names[foeId];
  const body={
    talbot:[G.flags.talbotUnhorsed?
      '第三合未到，塔尔博已被你一枪挑离鞍桥，摔在栅栏边半天没爬起来。他坐在土里摘了盔，喘得像头真野猪，半晌，闷声道："……好枪。"':
      '三合已毕，司仪举旗向你。塔尔博摘下头盔，啐了口唾沫，却咧嘴笑了："痛快！多少年没挨过这么正的一枪了。"'],
    edmund:['埃德蒙爵士缓缓收剑归鞘，摘下头盔。白发汗湿。"漂亮的虚招。"老骑士说，"三十年没人这么骗过我了。"'],
    belloc:[sharp?'利剑抵在喉甲之前，贝洛克僵立不动。满场屏息——谁都看得见，这一剑收与不收，全在你。':
      '贝洛克的钝剑落了地。黑塔倾颓，单膝点尘。全场诸侯都站了起来。'],
  }[foeId];
  const choices=[];
  choices.push({label:'扶他起身，分文不取', sub:'胜负已分，恩怨两清。', fx:()=>{
    G.v.ren++; G.v.li++;
    deed(`胜${nm}而免其赎金`);
    if(foeId==='belloc') bellocAfter(true,next); else afterYieldFlavor(foeId,next);
  }});
  choices.push({label:'依例收取赎金', sub:'（钱袋 +5）赎俘乃古例，并非不义。', fx:()=>{
    G.coins+=5; sfx.coin(); deed(`胜${nm}，依例收赎金五银`);
    if(foeId==='belloc') bellocAfter(false,next); else afterYieldFlavor(foeId,next);
  }});
  if(sharp) choices.push({label:'手起，剑落', sub:'利剑之约，本就许人生死。', fx:()=>{
    stain('阵斩已降之敌'); G.v.ren-=3;
    showPanel({title:'终阵 · 血',
      body:['满场死寂。方才还在喝彩的人们，一个一个坐了回去，没有人看你。',
        '司仪官别过脸，把桂冠放在台上，像放下一件脏东西。'],
      choices:[{label:'……', fx:next}]});
  }});
  showPanel({title:`${nm} 降伏`, body, choices});
}
function afterYieldFlavor(foeId,next){
  if(foeId==='edmund'){
    showPanel({title:'灰鹭之言',
      body:['埃德蒙爵士与你并肩走下场。"小子，"他忽然说，"终阵的贝洛克，最恨别人稳得住。你越不动气，他越要出错。"'],
      choices:[{label:'谢过老骑士', fx:next}]});
  } else next();
}
function bellocAfter(merciful,next){
  const grudge=G.flags.baronGrudge, helped=grudge||G.deeds.some(d=>d.includes('寡妇'));
  if(merciful&&helped){
    showPanel({title:'黑塔起身',
      body:['你伸手，贝洛克盯着那只手看了很久，终于握住，借力起身。',
        '他摘下手套，声音不大，却足够近处的诸侯听见："沙溪村……今年的秋租，<em>减半</em>。"',
        '他顿了顿："败军之将不敢言勇。但男爵的话，还是话。"'],
      choices:[{label:'……', fx:next}]});
  } else next();
}
/* ================= 终幕 ================= */
function finale(){
  G.flags.champion=!G.stains.some(s=>s.includes('阵斩'));
  const oath=G.oaths[0];
  if(oath&&oath.kept===null){
    showPanel({
      title:'高台之上',
      body:['司仪官托着桂冠走来。台下诸侯齐聚，<em>贝洛克男爵</em>也在其列。',
        '万众目光都在你身上——你想起沙溪村，想起那句立过的誓。此刻开口，正是时候；不开口，也没人知道你许过什么。'],
      choices:[
        {label:'当众陈情：请为沙溪村减免秋租', sub:'一诺既出，虽千万人。', fx:()=>{
          oath.kept=true; G.v.xin+=2; G.v.yi++;
          deed('冠冕之下，不忘为沙溪村践诺陈情');
          showPanel({title:'高台之上',
            body:['台下静了片刻。几位诸侯交换眼色——胜者开口，第一句竟不是讨封赏。',
              '贝洛克面色数变，终是在众目之下缓缓点头："……准。"',
              '人群后排，有个抱孩子的妇人哭出了声。'],
            choices:[{label:'受冠', fx:prizeStep}]});
        }},
        {label:'缄默受冠', sub:'那个誓，无人记得。', fx:()=>{
          oath.kept=false; G.v.xin-=2;
          deed('受冠而忘沙溪村之诺');
          prizeStep();
        }},
      ],
    });
  } else prizeStep();
}
function prizeStep(){
  if(!G.flags.champion){ shieldScreen(); return; }
  G.coins+=10;
  showPanel({
    title:'奖金十银',
    body:['桂冠之外，另有奖金<em>十枚银币</em>，沉甸甸一小袋。','司仪官问："骑士，这袋银子，如何处置？"'],
    quiet:'慷慨（Largesse）乃骑士古德：所获散于人，名乃归于己。',
    choices:[
      {label:'尽数送往沙溪村', sub:'（钱袋不变）"给村里过冬。"', fx:()=>{
        G.coins-=10; G.v.yi++; G.v.ren++; deed('尽散奖金十银予沙溪村');
        shieldScreen();
      }},
      {label:'散予校场的老兵与侍从', sub:'（钱袋不变）从白须老侍从起。', fx:()=>{
        G.coins-=10; G.v.li++; G.v.ren++; deed('散奖金予校场老兵侍从');
        shieldScreen();
      }},
      {label:'收入行囊', sub:'（钱袋 +10）来日方长，处处要钱。', fx:()=>{
        deed('收奖金十银入囊');
        shieldScreen();
      }},
    ],
  });
}
function epithet(){
  const v=G.v;
  if(G.stains.length) return ['蒙尘之盾','德有亏，则盾有尘。尘可拭，痕难平。'];
  const five=[v.ren,v.yi,v.li,v.zhi,v.xin];
  if(five.every(x=>x>=1)) return ['君子之盾','五常俱备，表里如一。此盾无需纹饰，其行即其纹章。'];
  const names=['仁者之盾','守义之盾','知礼之盾','明智之盾','守信之盾'];
  const mx=Math.max(...five);
  if(mx<=0) return ['无铭之盾','一路行来，未曾多事，也未曾多情。盾面干净，也空空如也。'];
  return [names[five.indexOf(mx)],'一德独厚，余者尚缺。行游未尽，来日可期。'];
}
function shieldScreen(){
  G.scene='finale'; hud(); hint(''); duelHudHide();
  sfx.bell();
  buildFinaleShield();
  overlay.classList.add('side');
  const [title,judge]=epithet();
  const v=G.v;
  let body=[`<span style="font-size:22px;color:#E0B33C;letter-spacing:.2em">「${title}」</span>`, judge];
  if(v.shendu>=2&&!G.stains.length)
    body.push('<em>另有一行小字，刻在盾的内侧，只有持盾的人看得见：</em>「无人看见时，你仍是君子。」');
  if(G.flags.tookPurse)
    body.push('<span style="color:var(--ivory-dim)">盾的内侧也有一行小字：「苇渡口的流水，记得一件事。」</span>');
  body.push('—— 判词 ——');
  for(const d of G.deeds) body.push('· '+d);
  for(const s of G.stains) body.push(`<em>‡ ${s}（此痕不可拭去）</em>`);
  if(G.oaths.length){
    body.push('—— 誓约簿 ——');
    for(const o of G.oaths) body.push((o.kept?'✓ 已践':o.kept===false?'✗ 已违':'… 未了')+' · '+o.text);
  }
  showPanel({
    title:'盾面 · 终幕',
    body,
    quiet:'德行从不显示数值。它只是被记住了——被这个王国，也被你自己。',
    choices:[
      {label:'再行游一遭', sub:'另一条路，另一面盾。', fx:()=>location.reload()},
    ],
  });
}
/* ================= 序章 ================= */
function prologue(){
  showPanel({
    title:'序章 · 一纸誓词',
    body:['老王驾崩，无嗣。三家摄政各执玉玺残片，王国<em>裂而未崩</em>：律法还在，却无人执行；道路还通，却盗匪横行。',
      '你是新受封的骑士。无封地，无家名。一马，一剑，一纸誓词。',
      '三日后，圣奥仑比武大会开幕，诸侯齐聚。你的路，从营地前的这条土路开始。'],
    quiet:'本游戏不显示任何德行数值。你的所作所为，这个王国自会记得——终幕时，你的盾面便是你的一生。',
    choices:[{label:'上马', sub:'方向键或 WASD 骑行。路上遇事，皆由你断。', fx:()=>{ hint(MAP_HINT); }}],
  });
}
/* ================= 行游逻辑 ================= */
function tickMap(dt){
  let dx=0,dy=0;
  if(keys.ArrowLeft||keys.KeyA) dx-=1;
  if(keys.ArrowRight||keys.KeyD) dx+=1;
  if(keys.ArrowUp||keys.KeyW) dy-=1;
  if(keys.ArrowDown||keys.KeyS) dy+=1;
  player.moving=!!(dx||dy);
  if(dx||dy){
    const n=Math.hypot(dx,dy);
    player.x=clamp(player.x+dx/n*player.speed*dt, 30, MAP.w-30);
    player.y=clamp(player.y+dy/n*player.speed*dt, 30, MAP.h-30);
    player.a=Math.atan2(dy,dx);
  }
  for(const l of LOCS){
    if(!l.done && dist(player.x,player.y,l.x,l.y)<l.r){
      l.done=true; EVENTS[l.id]();
      break;
    }
  }
}
/* ================= 摄像机与渲染 ================= */
const camTmp=new THREE.Vector3(), lookTmp=new THREE.Vector3();
function angleLerp(a,b,k){
  let d=b-a;
  while(d>Math.PI) d-=Math.PI*2;
  while(d<-Math.PI) d+=Math.PI*2;
  return a+d*k;
}
let camInit=false, RIDER=null;
function ensureRider(){
  if(!RIDER&&modelsReady){
    RIDER=new Actor('knight',{show:['1H_Sword','Badge_Shield','Knight_Helmet','Knight_Cape'],scale:0.82});
    RIDER.play('Sit_Chair_Idle');
    RIDER.root.rotation.y=Math.PI/2;   /* 与马头同向（马身局部 +X 为前） */
    RIDER.root.position.set(-.02,1.22,0);
    horse.root.add(RIDER.root);
    horse.riderOld.visible=false;
  }
}
function renderMap(dt,t){
  ensureRider();
  if(RIDER) RIDER.mixer.update(dt);
  /* 马 */
  const hx=wx(player.x), hz=wz(player.y);
  horse.root.position.set(hx,0,hz);
  const targetYaw=player.moving?-player.a:horseYaw;
  horseYaw=angleLerp(horseYaw,targetYaw,lerpK(dt,8));
  horse.root.rotation.y=horseYaw;
  const gait=player.moving?1:0;
  horse.legs.forEach((g,i)=>{
    g.rotation.z=gait*Math.sin(t*11+ (i%2?Math.PI:0) + (i>1?Math.PI/2:0))*0.55;
  });
  horse.root.position.y=gait*Math.abs(Math.sin(t*11))*0.05;
  /* 浮标 */
  for(const m of markers){
    m.g.visible=!m.loc.done;
    m.d.rotation.y=t*1.4; m.d.position.y=2.6+Math.sin(t*2.2)*0.15;
  }
  /* 太阳跟随（保证影子覆盖） */
  const sun=mapScene.userData.sun;
  sun.position.set(hx+18,26,hz+10); sun.target.position.set(hx,0,hz);
  /* 相机 */
  camTmp.set(hx,0,hz).add(new THREE.Vector3(0,10.4,9.8));
  if(!camInit){ camera.position.copy(camTmp); camInit=true; }
  camera.position.lerp(camTmp,lerpK(dt,5));
  lookTmp.set(hx,1.1,hz-1.2);
  camera.lookAt(lookTmp);
  renderer.render(mapScene,camera);
}
let orbitA=0, baseFov=46;
function renderDuel(dt,t){
  if(duel&&P_ACT&&E_ACT){
    const p=duel.p,e=duel.e;
    P_ACT.root.position.x=(p.x-480)*S;
    E_ACT.root.position.x=(e.x-480)*S;
    syncActor(P_ACT,p,dt);
    syncActor(E_ACT,e,dt);
    duelHudTick();
  }
  /* 旗帜摆动 */
  duelScene.userData.flags.forEach((f,i)=>{ f.rotation.y=Math.sin(t*1.8+i)*0.25; });
  tickSparks(dt);
  /* 环绕运镜：镜头绕决斗者中点缓慢扫动 */
  const mid=duel?((duel.p.x+duel.e.x)/2-480)*S:0;
  const gapW=duel?Math.abs(duel.e.x-duel.p.x)*S:6;
  let targetA, R, h, lookY;
  if(duel&&duel.phase==='salute'){
    targetA=Math.sin(t*0.35)*1.15;                 /* 开场大幅低机位环视 */
    R=3.6+gapW*0.35; h=1.15; lookY=1.15;
  }else if(duel&&duel.over){
    orbitA+=dt*0.45;                               /* 结算：缓慢绕行跪降者 */
    targetA=orbitA;
    R=3.2; h=1.5; lookY=0.95;
  }else{
    targetA=Math.sin(t*0.16)*0.72;                 /* 战斗中限幅扫动，保持左右可读 */
    R=4.0+gapW*0.5; h=1.55+gapW*0.06; lookY=1.05;
  }
  if(!(duel&&duel.over)) orbitA+=(targetA-orbitA)*lerpK(dt,1.6);
  const cx=mid+Math.sin(orbitA)*R;
  const cz=Math.cos(orbitA)*R;
  camTmp.set(cx,h,cz);
  camera.position.lerp(camTmp,lerpK(dt,4));
  shake=Math.max(0,shake-dt*1.6);
  if(shake>0){
    camera.position.x+=(Math.random()-.5)*shake*.18;
    camera.position.y+=(Math.random()-.5)*shake*.14;
  }
  /* 命中时轻微推近（FOV 冲击） */
  const wantFov=baseFov-shake*7;
  if(Math.abs(camera.fov-wantFov)>0.05){ camera.fov+=(wantFov-camera.fov)*lerpK(dt,10); camera.updateProjectionMatrix(); }
  lookTmp.set(mid,lookY,0);
  camera.lookAt(lookTmp);
  renderer.render(duelScene,camera);
}
function renderFinale(dt,t){
  if(shieldMesh){ shieldMesh.rotation.y=Math.sin(t*0.5)*0.45; }
  camTmp.set(0,.6,6.4);
  camera.position.lerp(camTmp,lerpK(dt,3));
  camera.lookAt(0,.2,0);
  renderer.render(finaleScene,camera);
}
let titleT=0;
const dummyP={stance:1,state:'idle',exhaust:0,blockFlash:0,hurtFlash:0,vx:0,strikeStance:1,t:0};
const dummyE={stance:0,state:'idle',exhaust:0,blockFlash:0,hurtFlash:0,vx:0,strikeStance:0,t:0};
function renderTitle(dt,t){
  /* 用决斗场当标题背景：两名骑士对峙，镜头缓移 */
  titleT+=dt;
  if(modelsReady){
    ensurePlayerActor();
    if(!E_ACT) setFoeActor('belloc');
    P_ACT.root.position.x=-1.4; E_ACT.root.position.x=1.4;
    syncActor(P_ACT,dummyP,dt);
    syncActor(E_ACT,dummyE,dt);
  }
  duelScene.userData.flags.forEach((f,i)=>{ f.rotation.y=Math.sin(t*1.8+i)*0.25; });
  const a=titleT*0.06;
  camera.position.set(Math.sin(a)*7.5,2.1+Math.sin(titleT*0.13)*0.4,Math.cos(a)*7.5);
  camera.lookAt(0,1.15,0);
  renderer.render(duelScene,camera);
}
/* ================= 主循环 ================= */
const clock=new THREE.Clock();
function loop(){
  const dt=Math.min(clock.getDelta(),0.05);
  const t=clock.elapsedTime;
  if(G.scene==='map'){ if(!panelOpen) tickMap(dt); renderMap(dt,t); }
  else if(G.scene==='duel'){ if(!panelOpen) tickDuel(dt); renderDuel(dt,t); }
  else if(G.scene==='joust'){ if(!panelOpen) tickJoust(dt); renderJoust(dt,t); }
  else if(G.scene==='finale'){ renderFinale(dt,t); }
  else renderTitle(dt,t);
  sndTick(dt);
  clearPressed();
  requestAnimationFrame(loop);
}
loop();
/* 测试钩子 */
window.__DBG={G, player, LOCS, getDuel:()=>duel, getJoust:()=>joust, startDuel, startJoust,
  forceJoust:w=>{ if(joust) joust._force=w?'p':'e'; },
  EVENTS, finale, shieldScreen, endDuelToMap};
/* 模型就绪后才可启程 */
const startbtn=$('#startbtn');
startbtn.disabled=true; startbtn.textContent='铸　剑　中　…'; startbtn.style.opacity=.55;
loadModels().then(()=>{
  startbtn.disabled=false; startbtn.textContent='启　程'; startbtn.style.opacity=1;
  window.__DBG.modelsReady=true;
}).catch(e=>{ console.error('模型加载失败',e); startbtn.textContent='加载失败'; });
startbtn.addEventListener('click',()=>{
  ac();
  $('#title').style.display='none';
  G.scene='map'; hud(); sfx.horn();
  prologue();
});
