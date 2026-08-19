#!/usr/bin/env bash
set -euo pipefail

APP_DIR="$HOME/workspace/PureBaseballLiveV151"
APK_OUT="$HOME/workspace/퓨어야구분석기_V1.5.1_실전.apk"
RELEASE_TAG="baseball-v1.5.1-live"
RELEASE_TITLE="퓨어야구분석기 V1.5.1 실전"
REPO_DIR="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
BRANCH="$(git -C "$REPO_DIR" branch --show-current 2>/dev/null || echo main)"
REMOTE="$(git -C "$REPO_DIR" config --get remote.origin.url 2>/dev/null || true)"

if [[ "$REMOTE" =~ github.com[:/]([^/]+)/([^/.]+)(\.git)?$ ]]; then
  OWNER="${BASH_REMATCH[1]}"
  REPO="${BASH_REMATCH[2]}"
else
  OWNER=""
  REPO=""
fi

echo "================================================"
echo " 퓨어야구분석기 V1.5.1 실전"
echo " GitHub 중간 수집기 + APK + Release 자동"
echo "================================================"

echo "[1/8] Java/Python 준비..."
sudo apt-get update -y >/dev/null
sudo apt-get install -y openjdk-17-jdk wget unzip python3 python3-pip >/dev/null

JAVA17="/usr/lib/jvm/java-17-openjdk-amd64"
if [ ! -d "$JAVA17" ]; then
  JAVA17="$(dirname "$(dirname "$(readlink -f "$(command -v javac)")")")"
fi
export JAVA_HOME="$JAVA17"
export PATH="$JAVA_HOME/bin:$PATH"

echo "[2/8] GitHub 중간 수집기 생성..."
mkdir -p "$REPO_DIR/collector" "$REPO_DIR/live" "$REPO_DIR/.github/workflows"

cat > "$REPO_DIR/collector/baseball_collector.py" <<'PY'
import json, re, os, sys, datetime, urllib.request, urllib.parse
from html import unescape

KST = datetime.timezone(datetime.timedelta(hours=9))
NOW = datetime.datetime.now(KST)
TODAY = NOW.date()

HEADERS = {
    "User-Agent": "Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 Chrome/140 Safari/537.36",
    "Accept-Language": "ko-KR,ko;q=0.9,en;q=0.8",
    "Accept": "text/html,application/xhtml+xml,application/json;q=0.9,*/*;q=0.8",
}

def get(url, timeout=15):
    req = urllib.request.Request(url, headers=HEADERS)
    with urllib.request.urlopen(req, timeout=timeout) as r:
        return r.read().decode("utf-8", "ignore")

def get_json(url):
    return json.loads(get(url))

def kst_time(iso):
    try:
        dt=datetime.datetime.fromisoformat(iso.replace("Z","+00:00")).astimezone(KST)
        return dt.strftime("%H:%M"), dt.isoformat()
    except:
        return "", iso

def clean_html(x):
    x=re.sub(r"<script.*?</script>"," ",x,flags=re.S|re.I)
    x=re.sub(r"<style.*?</style>"," ",x,flags=re.S|re.I)
    x=re.sub(r"<[^>]+>"," ",x)
    return re.sub(r"\s+"," ",unescape(x)).strip()

def record_pct(w,l):
    try:
        w=int(w); l=int(l)
        return round(w/(w+l),4) if w+l else .5
    except: return .5

def mlb():
    games=[]
    date=TODAY.strftime("%Y-%m-%d")
    url=f"https://statsapi.mlb.com/api/v1/schedule?sportId=1&date={date}&hydrate=probablePitcher,team"
    data=get_json(url)
    for d in data.get("dates",[]):
        for g in d.get("games",[]):
            status=(g.get("status") or {}).get("abstractGameState","")
            detailed=(g.get("status") or {}).get("detailedState","")
            t, iso=kst_time(g.get("gameDate",""))
            away=(g.get("teams") or {}).get("away",{})
            home=(g.get("teams") or {}).get("home",{})
            ap=(away.get("probablePitcher") or {}).get("fullName","")
            hp=(home.get("probablePitcher") or {}).get("fullName","")
            games.append({
                "source":"MLB StatsAPI",
                "league":"MLB",
                "gamePk":str(g.get("gamePk","")),
                "timeKST":t,
                "startISO":iso,
                "status": "경기전" if status=="Preview" else ("종료" if status=="Final" else "경기중"),
                "statusDetail":detailed,
                "away":(away.get("team") or {}).get("name",""),
                "home":(home.get("team") or {}).get("name",""),
                "awayWins":away.get("leagueRecord",{}).get("wins"),
                "awayLosses":away.get("leagueRecord",{}).get("losses"),
                "homeWins":home.get("leagueRecord",{}).get("wins"),
                "homeLosses":home.get("leagueRecord",{}).get("losses"),
                "awayWinPct":record_pct(away.get("leagueRecord",{}).get("wins",0),away.get("leagueRecord",{}).get("losses",0)),
                "homeWinPct":record_pct(home.get("leagueRecord",{}).get("wins",0),home.get("leagueRecord",{}).get("losses",0)),
                "awayStarter":ap,
                "homeStarter":hp,
            })
    return games

def kbo_official():
    # Official English scoreboard. Parsing is intentionally conservative.
    games=[]
    ds=TODAY.strftime("%Y%m%d")
    urls=[
        f"https://eng.koreabaseball.com/Schedule/Scoreboard.aspx?gameDate={ds}",
        "https://eng.koreabaseball.com/Schedule/Scoreboard.aspx",
    ]
    html=""
    for u in urls:
        try:
            html=get(u)
            if len(html)>1000: break
        except: pass
    if not html: return games

    # Extract visible text around HH:MM / VS blocks. Unknown layouts are not guessed.
    text=clean_html(html)
    teams=["LG","HANWHA","KIA","SAMSUNG","LOTTE","DOOSAN","KT","SSG","NC","KIWOOM"]
    aliases={"HANWHA":"Hanwha","SAMSUNG":"Samsung","LOTTE":"Lotte","DOOSAN":"Doosan","KIWOOM":"Kiwoom"}
    # Generic pair finder around time.
    pat=re.compile(r"(\d{1,2}:\d{2}).{0,100}?("+"|".join(teams)+r").{0,80}?("+"|".join(teams)+r")",re.I)
    seen=set()
    for m in pat.finditer(text):
        a,b=m.group(2).upper(),m.group(3).upper()
        if a==b: continue
        key=m.group(1)+"|"+a+"|"+b
        if key in seen: continue
        seen.add(key)
        games.append({
            "source":"KBO Official",
            "league":"KBO","gamePk":key,
            "timeKST":m.group(1),"startISO":"",
            "status":"경기전",
            "away":aliases.get(a,a),"home":aliases.get(b,b),
            "awayWins":None,"awayLosses":None,"homeWins":None,"homeLosses":None,
            "awayWinPct":.5,"homeWinPct":.5,
            "awayStarter":"","homeStarter":""
        })
    return games

def npb_official():
    # Official NPB schedule page; conservative text parser.
    games=[]
    urls=[
        "https://npb.jp/games/",
        "https://npb.jp/bis/eng/2026/games/"
    ]
    html=""
    for u in urls:
        try:
            html=get(u)
            if len(html)>1000: break
        except: pass
    if not html: return games
    text=clean_html(html)
    names=["SoftBank","Hawks","Hanshin","Tigers","Giants","Yomiuri","BayStars","DeNA","Carp",
           "Yakult","Swallows","Dragons","Chunichi","Buffaloes","Orix","Fighters","Nippon-Ham",
           "Marines","Lotte","Eagles","Rakuten","Lions","Seibu"]
    pat=re.compile(r"(\d{1,2}:\d{2}).{0,100}?("+"|".join(map(re.escape,names))+r").{0,80}?("+"|".join(map(re.escape,names))+r")",re.I)
    seen=set()
    for m in pat.finditer(text):
        a,b=m.group(2),m.group(3)
        if a.lower()==b.lower(): continue
        key=m.group(1)+"|"+a+"|"+b
        if key in seen: continue
        seen.add(key)
        games.append({
            "source":"NPB Official",
            "league":"NPB","gamePk":key,"timeKST":m.group(1),"startISO":"",
            "status":"경기전","away":a,"home":b,
            "awayWins":None,"awayLosses":None,"homeWins":None,"homeLosses":None,
            "awayWinPct":.5,"homeWinPct":.5,"awayStarter":"","homeStarter":""
        })
    return games

def livescore_backup():
    # Optional backup only. 403 is expected on some networks and is not fatal.
    try:
        html=get("https://livescore.co.kr/sports/score_board/baseball_score.php")
        return {"ok":True,"bytes":len(html)}
    except Exception as e:
        return {"ok":False,"error":type(e).__name__+": "+str(e)[:120]}

def main():
    result={
        "generatedAt":NOW.isoformat(),
        "dateKST":TODAY.isoformat(),
        "mode":"PRE_GAME_ONLY",
        "oddsUsedForAnalysis":False,
        "sources":{},
        "games":[]
    }
    collectors=[("MLB",mlb),("KBO",kbo_official),("NPB",npb_official)]
    for name,fn in collectors:
        try:
            x=fn()
            result["games"].extend(x)
            result["sources"][name]={"ok":True,"games":len(x)}
        except Exception as e:
            result["sources"][name]={"ok":False,"error":type(e).__name__+": "+str(e)[:160]}
    result["sources"]["LivescoreBackup"]=livescore_backup()

    # Never invent games. Empty league stays empty and app will PASS.
    os.makedirs("live",exist_ok=True)
    with open("live/baseball.json","w",encoding="utf-8") as f:
        json.dump(result,f,ensure_ascii=False,indent=2)
    print(json.dumps(result["sources"],ensure_ascii=False))

if __name__=="__main__":
    main()
PY

cat > "$REPO_DIR/.github/workflows/baseball-live-data.yml" <<'YML'
name: Baseball Live Data

on:
  workflow_dispatch:
  schedule:
    - cron: "*/20 * * * *"

permissions:
  contents: write

jobs:
  collect:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - name: Collect pre-game baseball data
        run: python3 collector/baseball_collector.py
      - name: Commit live JSON
        run: |
          git config user.name "baseball-data-bot"
          git config user.email "actions@users.noreply.github.com"
          git add live/baseball.json
          git diff --cached --quiet && exit 0
          git commit -m "Update baseball pre-game data"
          git push
YML

cd "$REPO_DIR"
python3 collector/baseball_collector.py || true

if [ -n "$OWNER" ] && [ -n "$REPO" ]; then
  DATA_URL="https://raw.githubusercontent.com/$OWNER/$REPO/$BRANCH/live/baseball.json"
else
  DATA_URL="https://raw.githubusercontent.com/OWNER/REPO/main/live/baseball.json"
fi

echo "중간 JSON 주소: $DATA_URL"

echo "[3/8] Android 앱 생성..."
rm -rf "$APP_DIR"
mkdir -p "$APP_DIR/app/src/main/java/com/pureanalysis/baseball/livev151"
mkdir -p "$APP_DIR/app/src/main/res/values"
mkdir -p "$APP_DIR/app/src/main/res/drawable"

cat > "$APP_DIR/settings.gradle" <<'EOF'
pluginManagement { repositories { google(); mavenCentral(); gradlePluginPortal() } }
dependencyResolutionManagement {
    repositoriesMode.set(RepositoriesMode.FAIL_ON_PROJECT_REPOS)
    repositories { google(); mavenCentral() }
}
rootProject.name="PureBaseballLiveV151"
include(":app")
EOF

cat > "$APP_DIR/build.gradle" <<'EOF'
plugins { id 'com.android.application' version '8.5.2' apply false }
EOF

cat > "$APP_DIR/gradle.properties" <<EOF
org.gradle.jvmargs=-Xmx2048m -Dfile.encoding=UTF-8
android.useAndroidX=true
org.gradle.java.home=$JAVA_HOME
EOF

cat > "$APP_DIR/app/build.gradle" <<'EOF'
plugins { id 'com.android.application' }
android {
    namespace 'com.pureanalysis.baseball.livev151'
    compileSdk 35
    defaultConfig {
        applicationId "com.pureanalysis.baseball.livev151"
        minSdk 26
        targetSdk 35
        versionCode 8
        versionName "1.5.1"
    }
}
EOF

cat > "$APP_DIR/app/src/main/AndroidManifest.xml" <<'EOF'
<manifest xmlns:android="http://schemas.android.com/apk/res/android">
  <uses-permission android:name="android.permission.INTERNET"/>
  <application android:label="퓨어야구 실전 V1.5.1" android:theme="@style/AppTheme">
    <activity android:name=".MainActivity" android:exported="true">
      <intent-filter>
        <action android:name="android.intent.action.MAIN"/>
        <category android:name="android.intent.category.LAUNCHER"/>
      </intent-filter>
    </activity>
  </application>
</manifest>
EOF

cat > "$APP_DIR/app/src/main/res/values/styles.xml" <<'EOF'
<resources>
 <style name="AppTheme" parent="android:style/Theme.Material.NoActionBar">
   <item name="android:fontFamily">sans</item>
   <item name="android:statusBarColor">#06101E</item>
   <item name="android:navigationBarColor">#06101E</item>
   <item name="android:windowLightStatusBar">false</item>
 </style>
</resources>
EOF

cat > "$APP_DIR/app/src/main/res/drawable/card_bg.xml" <<'EOF'
<shape xmlns:android="http://schemas.android.com/apk/res/android">
 <gradient android:startColor="#0D2038" android:endColor="#102A48" android:angle="0"/>
 <corners android:radius="20dp"/>
 <stroke android:width="1dp" android:color="#315C86"/>
</shape>
EOF

cat > "$APP_DIR/app/src/main/res/drawable/card_hi.xml" <<'EOF'
<shape xmlns:android="http://schemas.android.com/apk/res/android">
 <gradient android:startColor="#0E2845" android:endColor="#103459" android:angle="0"/>
 <corners android:radius="20dp"/>
 <stroke android:width="2dp" android:color="#31DCA1"/>
</shape>
EOF

cat > "$APP_DIR/app/src/main/res/drawable/btn_bg.xml" <<'EOF'
<shape xmlns:android="http://schemas.android.com/apk/res/android">
 <solid android:color="#1479F4"/>
 <corners android:radius="15dp"/>
</shape>
EOF

cat > "$APP_DIR/app/src/main/java/com/pureanalysis/baseball/livev151/MainActivity.java" <<EOF
package com.pureanalysis.baseball.livev151;

import android.app.*;
import android.os.*;
import android.graphics.*;
import android.graphics.Typeface;
import android.view.*;
import android.widget.*;
import android.content.*;
import org.json.*;
import java.io.*;
import java.net.*;
import java.nio.charset.StandardCharsets;
import java.text.*;
import java.util.*;

public class MainActivity extends Activity {
 static final String DATA_URL = "$DATA_URL";

 final int BG=Color.rgb(6,16,30), TEXT=Color.rgb(242,248,255), SUB=Color.rgb(158,182,207);
 final int BLUE=Color.rgb(61,165,255), GREEN=Color.rgb(55,221,161), YELLOW=Color.rgb(250,190,65), RED=Color.rgb(255,82,82);

 LinearLayout body;
 TextView status;
 SharedPreferences prefs;
 ArrayList<JSONObject> games=new ArrayList<>();

 @Override public void onCreate(Bundle b){
   super.onCreate(b); prefs=getSharedPreferences("locks151",MODE_PRIVATE); shell(); load();
 }

 int dp(int v){return (int)(v*getResources().getDisplayMetrics().density+.5f);}
 TextView tx(String s,int sp,int c,boolean bold){
   TextView t=new TextView(this);t.setText(s);t.setTextSize(sp);t.setTextColor(c);t.setPadding(0,dp(5),0,dp(5));
   if(bold)t.setTypeface(Typeface.DEFAULT,Typeface.BOLD);return t;
 }
 LinearLayout card(boolean hi){
   LinearLayout c=new LinearLayout(this);c.setOrientation(LinearLayout.VERTICAL);c.setPadding(dp(16),dp(14),dp(16),dp(14));
   c.setBackgroundResource(hi?R.drawable.card_hi:R.drawable.card_bg);
   LinearLayout.LayoutParams p=new LinearLayout.LayoutParams(-1,-2);p.setMargins(dp(10),dp(7),dp(10),dp(7));c.setLayoutParams(p);return c;
 }
 Button btn(String s){Button b=new Button(this);b.setText(s);b.setAllCaps(false);b.setTextColor(Color.WHITE);b.setBackgroundResource(R.drawable.btn_bg);return b;}

 void shell(){
   LinearLayout root=new LinearLayout(this);root.setOrientation(LinearLayout.VERTICAL);root.setBackgroundColor(BG);
   ScrollView sv=new ScrollView(this);body=new LinearLayout(this);body.setOrientation(LinearLayout.VERTICAL);sv.addView(body);

   LinearLayout h=card(false);
   h.addView(tx("⚾ 퓨어야구 분석기 V1.5.1 실전",23,TEXT,true));
   h.addView(tx("중간 수집기 연결 · PRE-GAME ONLY · 배당 분석 0%",13,BLUE,false));
   Button r=btn("↻ 실제 데이터 새로고침");r.setOnClickListener(v->load());h.addView(r);body.addView(h);

   LinearLayout n=card(false);
   n.addView(tx("🔒 실전 원칙",18,TEXT,true));
   n.addView(tx("경기전 데이터만 신규 분석 · 경기 시작 후 정보는 분석 차단",13,GREEN,true));
   n.addView(tx("정보 부족/수집 오류/후보 부족 → 강제 추천 없이 PASS",13,YELLOW,true));
   n.addView(tx("MLB 공식 우선 · KBO/NPB 공식 우선 · Livescore는 보조 확인만",13,SUB,false));
   body.addView(n);

   LinearLayout st=card(true);status=tx("중간 수집기 연결중...",16,BLUE,true);st.addView(status);body.addView(st);
   root.addView(sv,new LinearLayout.LayoutParams(-1,0,1));setContentView(root);
 }

 void load(){
   status.setText("GitHub 중간 JSON 수집중...");
   new Thread(()->{
     try{
       HttpURLConnection c=(HttpURLConnection)new URL(DATA_URL+"?t="+System.currentTimeMillis()).openConnection();
       c.setConnectTimeout(12000);c.setReadTimeout(12000);c.setRequestProperty("User-Agent","PureBaseball/1.5.1");
       int code=c.getResponseCode();if(code!=200)throw new IOException("HTTP "+code);
       String json=new String(c.getInputStream().readAllBytes(),StandardCharsets.UTF_8);
       JSONObject root=new JSONObject(json);
       JSONArray arr=root.optJSONArray("games");
       ArrayList<JSONObject> list=new ArrayList<>();
       if(arr!=null)for(int i=0;i<arr.length();i++)list.add(arr.getJSONObject(i));
       runOnUiThread(()->{games=list; rebuild(root);});
     }catch(Exception e){
       runOnUiThread(()->status.setText("⚠ 중간 수집기 연결 실패 → 분석 PASS\n"+e.getClass().getSimpleName()+": "+String.valueOf(e.getMessage())));
     }
   }).start();
 }

 double pct(JSONObject g,String side){
   return g.optDouble(side+"WinPct",.5);
 }
 double score(JSONObject g,String side){
   double s=50+(pct(g,side)-.5)*80;
   if("home".equals(side))s+=2.5;
   String starter=g.optString(side+"Starter","");
   if(!starter.isEmpty())s+=2.0;
   return s;
 }
 String grade(JSONObject g){
   if(!"경기전".equals(g.optString("status")))return "LOCK";
   double a=score(g,"away"),h=score(g,"home"),d=Math.abs(a-h),m=Math.max(a,h);
   if(d>=12&&m>=62)return "BLUE";
   if(d>=7&&m>=57)return "GREEN";
   if(d>=3)return "HOLD";
   return "OUT";
 }
 String pick(JSONObject g){
   return score(g,"away")>=score(g,"home")?g.optString("away"):g.optString("home");
 }
 int col(String gr){return gr.equals("BLUE")?BLUE:gr.equals("GREEN")?GREEN:gr.equals("HOLD")?YELLOW:gr.equals("OUT")?RED:SUB;}
 String ico(String gr){return gr.equals("BLUE")?"🔵":gr.equals("GREEN")?"🟢":gr.equals("HOLD")?"🟡":gr.equals("OUT")?"🔴":"🔒";}

 void rebuild(JSONObject root){
   while(body.getChildCount()>3)body.removeViewAt(3);
   int pre=0;for(JSONObject g:games)if("경기전".equals(g.optString("status")))pre++;
   status.setText("✅ 중간 수집기 정상 · "+root.optString("dateKST")+" · 전체 "+games.size()+"경기 / 경기전 "+pre+"경기");

   addSource(root);
   addCombo("🇺🇸 MLB 조합","MLB",false);
   addCombo("🇰🇷🇯🇵 KBO + NPB 조합","ASIA",true);
   addMulti();
   addLeague("🇺🇸 MLB","MLB",true);
   addLeague("🇰🇷 KBO","KBO",false);
   addLeague("🇯🇵 NPB","NPB",false);
 }

 ArrayList<JSONObject> candidates(String pool,String targetGrade){
   ArrayList<JSONObject> x=new ArrayList<>();
   for(JSONObject g:games){
     String l=g.optString("league");
     boolean ok=pool.equals("ASIA")?(l.equals("KBO")||l.equals("NPB")):l.equals(pool);
     if(ok&&targetGrade.equals(grade(g)))x.add(g);
   }
   x.sort((a,b)->Double.compare(Math.max(score(b,"away"),score(b,"home")),Math.max(score(a,"away"),score(a,"home"))));
   return x;
 }

 void addCombo(String title,String pool,boolean mixed){
   ArrayList<JSONObject> b=candidates(pool,"BLUE");LinearLayout c=card(true);c.addView(tx(title,19,TEXT,true));
   if(b.size()<2)c.addView(tx("PASS · 🔵 최종통과 2경기 미만",14,YELLOW,true));
   else{
     JSONObject a=b.get(0),d=b.get(1);
     c.addView(tx(mixed?"혼합/동일리그 조합 생성":"MLB 2경기 조합 생성",13,GREEN,true));
     c.addView(tx(a.optString("league")+" "+pick(a)+" 승 ("+a.optString("timeKST")+")",15,TEXT,true));
     c.addView(tx("+ "+d.optString("league")+" "+pick(d)+" 승 ("+d.optString("timeKST")+")",15,TEXT,true));
     c.addView(tx("※ 배당은 선별점수에 사용하지 않음",12,SUB,false));
   }body.addView(c);
 }

 void addMulti(){
   ArrayList<JSONObject> x=new ArrayList<>();
   for(JSONObject g:games){String gr=grade(g);if(gr.equals("BLUE")||gr.equals("GREEN"))x.add(g);}
   x.sort((a,b)->Double.compare(Math.max(score(b,"away"),score(b,"home")),Math.max(score(a,"away"),score(a,"home"))));
   LinearLayout c=card(false);c.addView(tx("💡 소액 다폴더픽",19,TEXT,true));
   if(x.size()<3)c.addView(tx("PASS · 조건충족 3경기 미만",14,YELLOW,true));
   else{
     int n=Math.min(4,x.size());
     for(int i=0;i<n;i++){JSONObject g=x.get(i);c.addView(tx("• "+g.optString("league")+" "+pick(g)+" 승 · "+g.optString("timeKST")+" · "+grade(g),14,TEXT,true));}
     c.addView(tx("※ 소액 다폴더도 조건 미달이면 PASS",12,GREEN,false));
   }body.addView(c);
 }

 void addLeague(String title,String league,boolean open){
   LinearLayout c=card(open);LinearLayout h=new LinearLayout(this);h.setGravity(Gravity.CENTER_VERTICAL);
   h.addView(tx(title,20,TEXT,true),new LinearLayout.LayoutParams(0,-2,1));TextView ar=tx(open?"⌃":"⌄",22,TEXT,true);h.addView(ar);c.addView(h);
   LinearLayout d=new LinearLayout(this);d.setOrientation(LinearLayout.VERTICAL);d.setVisibility(open?View.VISIBLE:View.GONE);
   int n=0;
   for(JSONObject g:games)if(league.equals(g.optString("league"))){
     n++;String gr=grade(g);String starter="";
     String as=g.optString("awayStarter",""),hs=g.optString("homeStarter","");
     if(!as.isEmpty()||!hs.isEmpty())starter="\n   선발: "+as+" / "+hs;
     d.addView(tx(ico(gr)+" "+g.optString("away")+" vs "+g.optString("home")+" · "+g.optString("timeKST")+" KST"+
       "\n   "+g.optString("status")+" · "+(gr.equals("OUT")||gr.equals("LOCK")?"신규추천 없음":"추천 "+pick(g)+" 승")+
       starter,13,col(gr),gr.equals("BLUE")));
   }
   if(n==0)d.addView(tx("수집된 오늘 경기 없음 → PASS",13,SUB,false));
   c.addView(d);h.setOnClickListener(v->{boolean v1=d.getVisibility()==View.VISIBLE;d.setVisibility(v1?View.GONE:View.VISIBLE);ar.setText(v1?"⌄":"⌃");});
   body.addView(c);
 }

 void addSource(JSONObject root){
   LinearLayout c=card(false);c.addView(tx("📡 중간 수집기 상태",18,TEXT,true));
   JSONObject s=root.optJSONObject("sources");
   if(s!=null){
     for(String k:new String[]{"MLB","KBO","NPB","LivescoreBackup"}){
       JSONObject z=s.optJSONObject(k);if(z==null)continue;
       c.addView(tx(k+": "+(z.optBoolean("ok")?"정상":"실패")+(z.has("games")?" · "+z.optInt("games")+"경기":""),13,z.optBoolean("ok")?GREEN:YELLOW,true));
     }
   }
   c.addView(tx("JSON 생성: "+root.optString("generatedAt"),12,SUB,false));
   body.addView(c);
 }
}
EOF

echo "[4/8] Gradle/Android SDK 준비..."
mkdir -p "$HOME/.local/gradle"
if [ ! -x "$HOME/.local/gradle/gradle-8.7/bin/gradle" ]; then
  wget -q https://services.gradle.org/distributions/gradle-8.7-bin.zip -O /tmp/gradle.zip
  unzip -q -o /tmp/gradle.zip -d "$HOME/.local/gradle"
fi
export PATH="$HOME/.local/gradle/gradle-8.7/bin:$PATH"

export ANDROID_HOME="$HOME/android-sdk"
export ANDROID_SDK_ROOT="$ANDROID_HOME"
rm -rf "$ANDROID_HOME/cmdline-tools/latest"
mkdir -p "$ANDROID_HOME/cmdline-tools/latest"
wget -q https://dl.google.com/android/repository/commandlinetools-linux-11076708_latest.zip -O /tmp/cmdtools.zip
rm -rf /tmp/cmdtools && mkdir -p /tmp/cmdtools
unzip -q /tmp/cmdtools.zip -d /tmp/cmdtools
cp -R /tmp/cmdtools/cmdline-tools/* "$ANDROID_HOME/cmdline-tools/latest/"
export PATH="$JAVA_HOME/bin:$ANDROID_HOME/cmdline-tools/latest/bin:$ANDROID_HOME/platform-tools:$PATH"
yes | "$ANDROID_HOME/cmdline-tools/latest/bin/sdkmanager" --licenses >/dev/null || true
"$ANDROID_HOME/cmdline-tools/latest/bin/sdkmanager" "platform-tools" "platforms;android-35" "build-tools;35.0.0" >/dev/null

echo "[5/8] 중간 수집기/워크플로 GitHub 저장..."
cd "$REPO_DIR"
git add collector/baseball_collector.py .github/workflows/baseball-live-data.yml live/baseball.json || true
if ! git diff --cached --quiet; then
  git config user.name "codespaces-builder"
  git config user.email "codespaces@users.noreply.github.com"
  git commit -m "Add baseball live collector V1.5.1" || true
  git push || echo "주의: 자동 push 실패. GitHub Source Control에서 Sync Changes를 눌러주세요."
fi

echo "[6/8] APK 빌드..."
cd "$APP_DIR"
gradle --no-daemon :app:assembleDebug
cp "$APP_DIR/app/build/outputs/apk/debug/app-debug.apk" "$APK_OUT"

echo "[7/8] GitHub Actions 수집 1회 실행 요청..."
if command -v gh >/dev/null 2>&1 && gh auth status >/dev/null 2>&1; then
  cd "$REPO_DIR"
  gh workflow run "Baseball Live Data" 2>/dev/null || true
fi

echo "[8/8] GitHub Release 자동 업로드..."
OK=0
if command -v gh >/dev/null 2>&1 && gh auth status >/dev/null 2>&1; then
  cd "$REPO_DIR"
  gh release delete "$RELEASE_TAG" -y --cleanup-tag >/dev/null 2>&1 || true
  if gh release create "$RELEASE_TAG" "$APK_OUT" \
      --title "$RELEASE_TITLE" \
      --notes "실전 V1.5.1

- GitHub 중간 수집기 방식
- MLB 공식 StatsAPI 우선
- KBO 공식 스코어보드 우선
- NPB 공식 일정 우선
- Livescore는 보조 확인, 403이어도 앱 정상 작동
- 20분 주기 데이터 갱신
- 경기전만 분석
- 데이터 부족 시 PASS
- MLB 2폴더
- KBO+NPB 혼합/동일 조합
- 소액 다폴더
- 배당은 분석에 사용하지 않음"; then
    OK=1
  fi
fi

echo ""
echo "================================================"
echo "완료!"
echo "중간 데이터: $DATA_URL"
echo "APK: $APK_OUT"
if [ "$OK" -eq 1 ]; then
  echo "Release: GitHub → Releases → $RELEASE_TAG"
else
  echo "Release 자동 업로드 실패/건너뜀. APK는 ~/workspace 에 있습니다."
fi
echo ""
echo "중요:"
echo "GitHub Actions 탭에서 'Baseball Live Data'가 실행되면"
echo "live/baseball.json 이 자동 갱신됩니다."
echo "================================================"
