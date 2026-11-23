import sharp from 'sharp';
import { mkdir, writeFile } from 'node:fs/promises';
import { resolve } from 'node:path';
const root=process.cwd();
const svg=Buffer.from(`<svg xmlns="http://www.w3.org/2000/svg" width="512" height="512" viewBox="0 0 512 512"><rect width="512" height="512" rx="116" fill="#0b1424"/><circle cx="256" cy="256" r="188" fill="none" stroke="#287be0" stroke-width="22"/><path d="M151 358V154h54l102 126V154h54v204h-51L205 229v129z" fill="#f7fbff"/><path d="M151 358 361 154" fill="none" stroke="#63c7ff" stroke-width="13" stroke-linecap="round"/><path d="M109 256h34M369 256h34" stroke="#63c7ff" stroke-width="12" stroke-linecap="round"/></svg>`);
const fg=Buffer.from(`<svg xmlns="http://www.w3.org/2000/svg" width="512" height="512" viewBox="0 0 512 512"><circle cx="256" cy="256" r="188" fill="none" stroke="#287be0" stroke-width="22"/><path d="M151 358V154h54l102 126V154h54v204h-51L205 229v129z" fill="#f7fbff"/><path d="M151 358 361 154" fill="none" stroke="#63c7ff" stroke-width="13" stroke-linecap="round"/></svg>`);
const assets=resolve(root,'assets');await mkdir(assets,{recursive:true});
for(const [size,name] of [[192,'icon-192.png'],[512,'icon-512.png'],[512,'icon-maskable-512.png']])await sharp(svg).resize(size,size).png().toFile(resolve(assets,name));
const res=resolve(root,'android/app/src/main/res');
for(const [density,size] of Object.entries({mdpi:48,hdpi:72,xhdpi:96,xxhdpi:144,xxxhdpi:192})){
 const dir=resolve(res,'mipmap-'+density);await mkdir(dir,{recursive:true});
 await sharp(svg).resize(size,size).png().toFile(resolve(dir,'ic_launcher.png'));
 await sharp(svg).resize(size,size).png().toFile(resolve(dir,'ic_launcher_round.png'));
 await sharp(fg).resize(size,size).png().toFile(resolve(dir,'ic_launcher_foreground.png'));
}
const adaptive=resolve(res,'mipmap-anydpi-v26');await mkdir(adaptive,{recursive:true});
const xml='<adaptive-icon xmlns:android="http://schemas.android.com/apk/res/android"><background android:drawable="@color/ic_launcher_background"/><foreground android:drawable="@mipmap/ic_launcher_foreground"/></adaptive-icon>';
await writeFile(resolve(adaptive,'ic_launcher.xml'),xml);await writeFile(resolve(adaptive,'ic_launcher_round.xml'),xml);
const values=resolve(res,'values');await mkdir(values,{recursive:true});await writeFile(resolve(values,'ic_launcher_background.xml'),'<resources><color name="ic_launcher_background">#0b1424</color></resources>');
console.log('IRONNOVA web and Android launcher icons generated.');
