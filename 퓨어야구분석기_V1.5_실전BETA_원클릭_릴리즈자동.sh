#!/usr/bin/env bash
set -euo pipefail

APP_DIR="$HOME/workspace/PureBaseballLiveV15"
APK_OUT="$HOME/workspace/퓨어야구분석기_V1.5_실전BETA.apk"
RELEASE_TAG="baseball-v1.5-live-beta"
RELEASE_TITLE="퓨어야구분석기 V1.5 실전 BETA"

echo "================================================"
echo " 퓨어야구분석기 V1.5 실전 BETA"
echo " Livescore 실제 경기 수집 / PRE-GAME ONLY"
echo "================================================"

mkdir -p "$HOME/workspace"
rm -rf "$APP_DIR"
mkdir -p "$APP_DIR/app/src/main/java/com/pureanalysis/baseball/livev15"
mkdir -p "$APP_DIR/app/src/main/res/values"
mkdir -p "$APP_DIR/app/src/main/res/drawable"

echo "[1/6] Java 17 준비..."
sudo apt-get update -y >/dev/null
sudo apt-get install -y openjdk-17-jdk wget unzip >/dev/null

JAVA17="/usr/lib/jvm/java-17-openjdk-amd64"
if [ ! -d "$JAVA17" ]; then
  JAVA17="$(dirname "$(dirname "$(readlink -f "$(command -v javac)")")")"
fi
export JAVA_HOME="$JAVA17"
export PATH="$JAVA_HOME/bin:$PATH"

cat > "$APP_DIR/settings.gradle" <<'EOF'
pluginManagement {
    repositories { google(); mavenCentral(); gradlePluginPortal() }
}
dependencyResolutionManagement {
    repositoriesMode.set(RepositoriesMode.FAIL_ON_PROJECT_REPOS)
    repositories { google(); mavenCentral() }
}
rootProject.name="PureBaseballLiveV15"
include(":app")
EOF

cat > "$APP_DIR/build.gradle" <<'EOF'
plugins {
    id 'com.android.application' version '8.5.2' apply false
}
EOF

cat > "$APP_DIR/gradle.properties" <<EOF
org.gradle.jvmargs=-Xmx2048m -Dfile.encoding=UTF-8
android.useAndroidX=true
org.gradle.java.home=$JAVA_HOME
EOF

cat > "$APP_DIR/app/build.gradle" <<'EOF'
plugins { id 'com.android.application' }

android {
    namespace 'com.pureanalysis.baseball.livev15'
    compileSdk 35
    defaultConfig {
        applicationId "com.pureanalysis.baseball.livev15"
        minSdk 26
        targetSdk 35
        versionCode 7
        versionName "1.5-beta"
    }
    buildTypes {
        debug { debuggable true }
        release { minifyEnabled false }
    }
}

dependencies {
    implementation 'org.jsoup:jsoup:1.17.2'
}
EOF

cat > "$APP_DIR/app/src/main/AndroidManifest.xml" <<'EOF'
<manifest xmlns:android="http://schemas.android.com/apk/res/android">
    <uses-permission android:name="android.permission.INTERNET"/>
    <uses-permission android:name="android.permission.POST_NOTIFICATIONS"/>
    <uses-permission android:name="android.permission.WAKE_LOCK"/>
    <application
        android:allowBackup="true"
        android:label="퓨어야구 실전BETA"
        android:theme="@style/AppTheme"
        android:usesCleartextTraffic="false">
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
        <item name="android:colorAccent">#3AA8FF</item>
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

cat > "$APP_DIR/app/src/main/java/com/pureanalysis/baseball/livev15/MainActivity.java" <<'EOF'
package com.pureanalysis.baseball.livev15;

import android.app.*;
import android.os.*;
import android.graphics.*;
import android.graphics.Typeface;
import android.view.*;
import android.widget.*;
import android.content.*;
import org.jsoup.*;
import org.jsoup.nodes.*;
import org.jsoup.select.*;
import org.json.*;
import java.text.*;
import java.util.*;
import java.util.regex.*;

public class MainActivity extends Activity {

    static final String SOURCE="https://livescore.co.kr/sports/score_board/baseball_score.php";

    static class Team {
        String name="";
        int wins=-1, draws=0, losses=-1;
        double era=-1;
        int pitcherWins=-1, pitcherLosses=-1;
        String pitcher="";
        boolean home=false;

        double winPct(){
            if(wins<0 || losses<0 || wins+losses==0) return .5;
            return (double)wins/(wins+losses);
        }
    }

    static class Game {
        String league="", time="", status="", id="";
        Team away=new Team(), home=new Team();
        String raw="";
        double awayScore=50, homeScore=50;
        String pick="", grade="HOLD", reason="";
        boolean pregame=false;
    }

    final int BG=Color.rgb(6,16,30), CARD=Color.rgb(13,32,56), TEXT=Color.rgb(242,248,255);
    final int SUB=Color.rgb(158,182,207), BLUE=Color.rgb(61,165,255), GREEN=Color.rgb(55,221,161);
    final int YELLOW=Color.rgb(250,190,65), RED=Color.rgb(255,82,82);

    LinearLayout body;
    TextView stateText, updated;
    Button refresh;
    final ArrayList<Game> games=new ArrayList<>();
    SharedPreferences prefs;

    @Override public void onCreate(Bundle b){
        super.onCreate(b);
        prefs=getSharedPreferences("locked_pregame",MODE_PRIVATE);
        renderShell();
        fetchLive();
    }

    int dp(int v){ return (int)(v*getResources().getDisplayMetrics().density+.5f); }

    TextView tx(String s,int sp,int color,boolean bold){
        TextView t=new TextView(this); t.setText(s); t.setTextSize(sp); t.setTextColor(color);
        t.setPadding(0,dp(4),0,dp(4)); if(bold)t.setTypeface(Typeface.DEFAULT,Typeface.BOLD); return t;
    }

    LinearLayout card(boolean hi){
        LinearLayout c=new LinearLayout(this); c.setOrientation(LinearLayout.VERTICAL);
        c.setPadding(dp(16),dp(14),dp(16),dp(14)); c.setBackgroundResource(hi?R.drawable.card_hi:R.drawable.card_bg);
        LinearLayout.LayoutParams p=new LinearLayout.LayoutParams(-1,-2); p.setMargins(dp(10),dp(7),dp(10),dp(7)); c.setLayoutParams(p);
        return c;
    }

    Button btn(String s){
        Button b=new Button(this); b.setText(s); b.setAllCaps(false); b.setTextColor(Color.WHITE); b.setTextSize(14);
        b.setBackgroundResource(R.drawable.btn_bg); return b;
    }

    void renderShell(){
        LinearLayout root=new LinearLayout(this); root.setOrientation(LinearLayout.VERTICAL); root.setBackgroundColor(BG);
        ScrollView sv=new ScrollView(this); body=new LinearLayout(this); body.setOrientation(LinearLayout.VERTICAL);
        body.setPadding(dp(4),dp(10),dp(4),dp(14)); sv.addView(body);

        LinearLayout h=card(false);
        h.addView(tx("⚾ 퓨어야구 분석기 V1.5 실전 BETA",23,TEXT,true));
        h.addView(tx("Livescore 실제 경기수집 · 배당 분석 0% · PRE-GAME ONLY",13,BLUE,false));
        updated=tx("마지막 수집: 대기중",12,SUB,false); h.addView(updated);
        refresh=btn("↻ 실제 경기 새로고침 / 재분석");
        refresh.setOnClickListener(v->fetchLive());
        h.addView(refresh);
        body.addView(h);

        LinearLayout notice=card(false);
        notice.addView(tx("🔒 실전 검증 원칙",18,TEXT,true));
        notice.addView(tx("• '경기전' 상태만 추천 계산",13,GREEN,true));
        notice.addView(tx("• 경기중 스코어/안타/실점/투구내용은 분석에 사용하지 않음",13,YELLOW,true));
        notice.addView(tx("• 경기 시작 전 확정픽은 휴대폰에 저장되어 LIVE 이후에도 유지",13,TEXT,false));
        notice.addView(tx("• 데이터 수집 실패/정보 부족 시 억지 추천 없이 PASS",13,TEXT,false));
        body.addView(notice);

        stateText=tx("실제 경기 데이터를 불러오는 중...",16,BLUE,true);
        LinearLayout s=card(true); s.addView(stateText); body.addView(s);

        addLockedSection();

        root.addView(sv,new LinearLayout.LayoutParams(-1,0,1));
        setContentView(root);
    }

    void fetchLive(){
        refresh.setEnabled(false);
        stateText.setText("Livescore 실제 경기표 수집중...");
        new Thread(()->{
            try{
                Document doc=Jsoup.connect(SOURCE)
                    .userAgent("Mozilla/5.0 (Linux; Android 16) AppleWebKit/537.36 Chrome/140 Mobile Safari/537.36")
                    .referrer("https://livescore.co.kr/?device=pc")
                    .timeout(15000)
                    .get();

                ArrayList<Game> parsed=parse(doc);
                runOnUiThread(()->{
                    games.clear(); games.addAll(parsed);
                    refresh.setEnabled(true);
                    String now=new SimpleDateFormat("MM-dd HH:mm:ss",Locale.KOREA).format(new Date());
                    updated.setText("마지막 수집: "+now+" KST");
                    rebuildLiveSections();
                });
            }catch(Exception e){
                runOnUiThread(()->{
                    refresh.setEnabled(true);
                    stateText.setText("⚠ 실제 데이터 수집 실패 → 분석 PASS\n"+e.getClass().getSimpleName()+": "+safe(e.getMessage()));
                });
            }
        }).start();
    }

    ArrayList<Game> parse(Document doc){
        ArrayList<Game> out=new ArrayList<>();
        HashSet<String> seen=new HashSet<>();

        // Livescore scoreboard is table-oriented. Each game table contains league/time/status + two team records.
        for(Element table:doc.select("table")){
            String text=clean(table.text());
            if(!(text.contains("MLB")||text.contains("KBO")||text.contains("NPB"))) continue;

            String league=find(text,"\\b(MLB|KBO|NPB)\\b");
            if(league.isEmpty()) continue;

            String status=text.contains("경기전")?"경기전":text.contains("종료")?"종료":text.contains("경기중")?"경기중":"";
            String time=find(text,"(오전|오후)?\\s*\\d{1,2}:\\d{2}");
            if(time.isEmpty()) continue;

            ArrayList<Team> teams=new ArrayList<>();
            for(Element tr:table.select("tr")){
                String rt=clean(tr.text());
                Matcher m=Pattern.compile("([^|]{1,30}?)\\s+(\\d{1,3})-(?:(\\d{1,2})-)?(\\d{1,3})\\s*\\((원정|홈)").matcher(rt);
                if(m.find()){
                    Team t=new Team();
                    t.name=cleanupTeam(m.group(1));
                    t.wins=num(m.group(2));
                    if(m.group(3)!=null)t.draws=num(m.group(3));
                    t.losses=num(m.group(4));
                    t.home="홈".equals(m.group(5));
                    parsePitcher(rt,t);
                    if(t.name.length()>0)teams.add(t);
                }
            }

            // Fallback for MLB 70-55 style without home/away token capture.
            if(teams.size()<2){
                Matcher m=Pattern.compile("([가-힣A-Za-z .·-]{2,24})\\s+(\\d{1,3})-(\\d{1,3})\\s*\\((원정|홈)").matcher(text);
                while(m.find() && teams.size()<2){
                    Team t=new Team();
                    t.name=cleanupTeam(m.group(1)); t.wins=num(m.group(2)); t.losses=num(m.group(3));
                    t.home="홈".equals(m.group(4));
                    teams.add(t);
                }
            }

            if(teams.size()<2) continue;

            Game g=new Game();
            g.league=league; g.time=time.trim(); g.status=status;
            g.away=teams.get(0); g.home=teams.get(1); g.raw=text;
            g.pregame="경기전".equals(status);
            g.id=league+"|"+g.away.name+"|"+g.home.name+"|"+g.time;

            if(seen.contains(g.id))continue;
            seen.add(g.id);

            analyze(g);
            out.add(g);
        }

        // If table boundary differs, parse page-level blocks approximately.
        if(out.isEmpty()){
            String all=clean(doc.body().text());
            Matcher head=Pattern.compile("(MLB|KBO|NPB)\\s+(오전|오후)?\\s*(\\d{1,2}:\\d{2})\\s+(경기전|종료|경기중)").matcher(all);
            while(head.find()){
                int st=head.start(), ed=Math.min(all.length(), head.end()+900);
                String block=all.substring(st,ed);
                Matcher tm=Pattern.compile("([가-힣A-Za-z .·-]{2,24})\\s+(\\d{1,3})-(?:(\\d{1,2})-)?(\\d{1,3})\\s*\\((원정|홈)").matcher(block);
                ArrayList<Team> ts=new ArrayList<>();
                while(tm.find()&&ts.size()<2){
                    Team t=new Team(); t.name=cleanupTeam(tm.group(1)); t.wins=num(tm.group(2));
                    if(tm.group(3)!=null)t.draws=num(tm.group(3)); t.losses=num(tm.group(4)); t.home="홈".equals(tm.group(5)); ts.add(t);
                }
                if(ts.size()==2){
                    Game g=new Game(); g.league=head.group(1); g.time=(safe(head.group(2))+" "+head.group(3)).trim();
                    g.status=head.group(4); g.away=ts.get(0); g.home=ts.get(1); g.pregame="경기전".equals(g.status);
                    g.id=g.league+"|"+g.away.name+"|"+g.home.name+"|"+g.time; analyze(g);
                    if(!seen.contains(g.id)){seen.add(g.id);out.add(g);}
                }
            }
        }

        return out;
    }

    void parsePitcher(String s,Team t){
        Matcher p=Pattern.compile("투수\\s*:\\s*([가-힣A-Za-z .·-]{2,30})").matcher(s);
        if(p.find())t.pitcher=p.group(1).trim();
        Matcher era=Pattern.compile("방어율\\s*([0-9]+(?:\\.[0-9]+)?)").matcher(s);
        if(era.find())try{t.era=Double.parseDouble(era.group(1));}catch(Exception ignored){}
        Matcher wl=Pattern.compile("(\\d+)승\\s*(\\d+)패").matcher(s);
        if(wl.find()){t.pitcherWins=num(wl.group(1));t.pitcherLosses=num(wl.group(2));}
    }

    void analyze(Game g){
        // No odds are parsed or used here.
        g.awayScore=baseTeamScore(g.away,false);
        g.homeScore=baseTeamScore(g.home,true);

        double diff=Math.abs(g.awayScore-g.homeScore);
        Team fav=g.awayScore>=g.homeScore?g.away:g.home;
        double favScore=Math.max(g.awayScore,g.homeScore);

        if(!g.pregame){
            g.grade="LOCKED"; g.pick=""; g.reason="경기 시작/종료 상태: 신규 분석 제외";
            return;
        }

        if(diff>=13 && favScore>=64){
            g.grade="BLUE"; g.pick=fav.name;
        }else if(diff>=8 && favScore>=59){
            g.grade="GREEN"; g.pick=fav.name;
        }else if(diff>=4){
            g.grade="HOLD"; g.pick=fav.name;
        }else{
            g.grade="OUT"; g.pick="";
        }

        StringBuilder r=new StringBuilder();
        r.append("시즌승률 ").append(String.format(Locale.US,"%.3f",fav.winPct()));
        if(fav.home)r.append(" · 홈경기");
        if(fav.era>0)r.append(" · 선발 ERA ").append(String.format(Locale.US,"%.2f",fav.era));
        if(fav.pitcher.length()>0)r.append(" (").append(fav.pitcher).append(")");
        r.append(" · 상대 점수차 ").append(String.format(Locale.US,"%.1f",diff));
        g.reason=r.toString();

        if("BLUE".equals(g.grade))lockPregame(g);
    }

    double baseTeamScore(Team t,boolean home){
        double s=50;
        s+=(t.winPct()-.5)*70.0;
        if(home)s+=2.5;
        if(t.era>0){
            double eraAdj=Math.max(-8,Math.min(8,(4.50-t.era)*3.0));
            s+=eraAdj;
        }
        if(t.pitcherWins>=0 && t.pitcherLosses>=0 && t.pitcherWins+t.pitcherLosses>0){
            double p=(double)t.pitcherWins/(t.pitcherWins+t.pitcherLosses);
            s+=(p-.5)*10;
        }
        return s;
    }

    void lockPregame(Game g){
        try{
            JSONObject o=new JSONObject();
            o.put("id",g.id); o.put("league",g.league); o.put("time",g.time);
            o.put("away",g.away.name); o.put("home",g.home.name);
            o.put("pick",g.pick); o.put("grade",g.grade); o.put("reason",g.reason);
            o.put("lockedAt",System.currentTimeMillis());
            prefs.edit().putString("g_"+g.id,o.toString()).apply();
        }catch(Exception ignored){}
    }

    void rebuildLiveSections(){
        // Remove everything after the first 4 cards: header, notice, state, locked section.
        while(body.getChildCount()>4) body.removeViewAt(4);

        int pre=0;
        for(Game g:games)if(g.pregame)pre++;
        stateText.setText("✅ 실제 데이터 연결 정상 · 전체 "+games.size()+"경기 · 경기전 "+pre+"경기");

        addComboCards();
        addLeagueAccordion("🇺🇸 MLB","MLB");
        addLeagueAccordion("🇰🇷 KBO","KBO");
        addLeagueAccordion("🇯🇵 NPB","NPB");
        addSourceCard();
    }

    ArrayList<Game> blue(String league){
        ArrayList<Game> a=new ArrayList<>();
        for(Game g:games)if(g.pregame&&league.equals(g.league)&&"BLUE".equals(g.grade))a.add(g);
        a.sort((x,y)->Double.compare(Math.max(y.awayScore,y.homeScore),Math.max(x.awayScore,x.homeScore)));
        return a;
    }

    void addComboCards(){
        ArrayList<Game> m=blue("MLB");
        addCombo("🇺🇸 MLB 조합",m);

        ArrayList<Game> asia=new ArrayList<>();asia.addAll(blue("KBO"));asia.addAll(blue("NPB"));
        asia.sort((x,y)->Double.compare(Math.max(y.awayScore,y.homeScore),Math.max(x.awayScore,x.homeScore)));
        addCombo("🇰🇷🇯🇵 KBO + NPB 조합",asia);

        ArrayList<Game> all=new ArrayList<>();
        for(Game g:games)if(g.pregame&&("BLUE".equals(g.grade)||"GREEN".equals(g.grade)))all.add(g);
        all.sort((x,y)->Double.compare(Math.max(y.awayScore,y.homeScore),Math.max(x.awayScore,x.homeScore)));
        addMulti(all);
    }

    void addCombo(String title,ArrayList<Game> list){
        LinearLayout c=card(true); c.addView(tx(title,19,TEXT,true));
        if(list.size()<2){
            c.addView(tx("PASS · 🔵 최종통과 2경기 미만",14,YELLOW,true));
        }else{
            Game a=list.get(0),b=list.get(1);
            c.addView(tx("조합픽 생성",13,GREEN,true));
            c.addView(tx(a.league+" "+a.pick+" 승 ("+a.time+")",16,TEXT,true));
            c.addView(tx("+ "+b.league+" "+b.pick+" 승 ("+b.time+")",16,TEXT,true));
            c.addView(tx("총 배당: 실전판 다음 단계에서 표시 · 분석에는 사용 안 함",12,SUB,false));
        }
        body.addView(c);
    }

    void addMulti(ArrayList<Game> all){
        LinearLayout c=card(false); c.addView(tx("💡 소액 다폴더 후보",19,TEXT,true));
        if(all.size()<3){
            c.addView(tx("PASS · 조건 충족 후보 3경기 미만",14,YELLOW,true));
        }else{
            int n=Math.min(4,all.size());
            for(int i=0;i<n;i++){
                Game g=all.get(i);
                c.addView(tx("• "+g.league+" "+g.pick+" 승 · "+g.time+" · "+g.grade,14,TEXT,true));
            }
            c.addView(tx("※ 다폴더도 배당을 보고 선별하지 않음",12,GREEN,false));
        }
        body.addView(c);
    }

    void addLeagueAccordion(String title,String league){
        LinearLayout c=card(false);
        LinearLayout head=new LinearLayout(this);head.setGravity(Gravity.CENTER_VERTICAL);
        head.addView(tx(title,20,TEXT,true),new LinearLayout.LayoutParams(0,-2,1));
        TextView ar=tx("⌄",22,TEXT,true);head.addView(ar);c.addView(head);

        LinearLayout d=new LinearLayout(this);d.setOrientation(LinearLayout.VERTICAL);d.setVisibility(View.GONE);
        int count=0;
        for(Game g:games){
            if(!league.equals(g.league))continue;
            count++;
            int col=g.grade.equals("BLUE")?BLUE:g.grade.equals("GREEN")?GREEN:g.grade.equals("HOLD")?YELLOW:g.grade.equals("OUT")?RED:SUB;
            String icon=g.grade.equals("BLUE")?"🔵":g.grade.equals("GREEN")?"🟢":g.grade.equals("HOLD")?"🟡":g.grade.equals("OUT")?"🔴":"🔒";
            String pick=g.pick.length()>0?"추천 "+g.pick:"신규추천 없음";
            d.addView(tx(icon+" "+g.away.name+" vs "+g.home.name+" · "+g.time+"\n"+
                    "   상태 "+g.status+" · "+pick+"\n   "+g.reason,13,col,"BLUE".equals(g.grade)));
        }
        if(count==0)d.addView(tx("현재 수집된 경기 없음",13,SUB,false));
        c.addView(d);
        head.setOnClickListener(v->{boolean open=d.getVisibility()==View.VISIBLE;d.setVisibility(open?View.GONE:View.VISIBLE);ar.setText(open?"⌄":"⌃");});
        body.addView(c);
    }

    void addLockedSection(){
        LinearLayout c=card(false);
        c.addView(tx("🔒 저장된 경기 전 확정픽",18,TEXT,true));
        Map<String,?> all=prefs.getAll();
        int n=0;
        for(Map.Entry<String,?> e:all.entrySet()){
            if(!e.getKey().startsWith("g_"))continue;
            try{
                JSONObject o=new JSONObject(String.valueOf(e.getValue()));
                c.addView(tx("🔵 "+o.optString("league")+" "+o.optString("away")+" vs "+o.optString("home")+" · "+o.optString("time")+
                    "\n   경기 전 확정: "+o.optString("pick")+" 승\n   "+o.optString("reason"),13,GREEN,true));
                n++;
            }catch(Exception ignored){}
        }
        if(n==0)c.addView(tx("아직 저장된 실전 확정픽 없음",13,SUB,false));
        body.addView(c);
    }

    void addSourceCard(){
        LinearLayout c=card(false);
        c.addView(tx("데이터 소스 / 안전장치",18,TEXT,true));
        c.addView(tx("1차 경기표: livescore.co.kr 야구 스코어보드",13,TEXT,false));
        c.addView(tx("분석 사용: 리그 · 팀 · 경기시간 · 경기상태 · 시즌성적 · 홈/원정 · 선발투수/ERA(수집 가능 시)",12,SUB,false));
        c.addView(tx("분석 미사용: 배당/라인 · LIVE 득점 · 이닝 · 안타 · 실시간 투구",12,YELLOW,true));
        c.addView(tx("⚠ V1.5는 실전 수집 BETA입니다. 사이트 구조가 바뀌면 데이터 오류 → PASS로 멈춥니다.",12,RED,false));
        body.addView(c);
    }

    static String find(String s,String re){Matcher m=Pattern.compile(re).matcher(s);return m.find()?m.group(1):"";}
    static int num(String s){try{return Integer.parseInt(s);}catch(Exception e){return 0;}}
    static String safe(String s){return s==null?"":s;}
    static String clean(String s){return s==null?"":s.replace('\u00a0',' ').replaceAll("\\s+"," ").trim();}
    static String cleanupTeam(String s){
        s=clean(s);
        s=s.replaceAll("^(MLB|KBO|NPB)\\s+","");
        s=s.replaceAll("^(Image:?\\s*)+","");
        s=s.replaceAll("[|]+","").trim();
        if(s.length()>30)s=s.substring(Math.max(0,s.length()-30));
        return s;
    }
}
EOF

echo "[2/6] Gradle 준비..."
mkdir -p "$HOME/.local/gradle"
if [ ! -x "$HOME/.local/gradle/gradle-8.7/bin/gradle" ]; then
  wget -q https://services.gradle.org/distributions/gradle-8.7-bin.zip -O /tmp/gradle.zip
  unzip -q -o /tmp/gradle.zip -d "$HOME/.local/gradle"
fi
export PATH="$HOME/.local/gradle/gradle-8.7/bin:$PATH"

echo "[3/6] Android SDK 준비..."
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

echo "[4/6] APK 빌드..."
cd "$APP_DIR"
gradle --no-daemon :app:assembleDebug

echo "[5/6] APK 복사..."
cp "$APP_DIR/app/build/outputs/apk/debug/app-debug.apk" "$APK_OUT"

echo "[6/6] GitHub Release 자동 업로드..."
OK=0
if command -v gh >/dev/null 2>&1 && gh auth status >/dev/null 2>&1; then
  REPO=""
  if [ -n "${GITHUB_REPOSITORY:-}" ] && [ -d "/workspaces/$(basename "$GITHUB_REPOSITORY")/.git" ]; then
    REPO="/workspaces/$(basename "$GITHUB_REPOSITORY")"
  else
    for d in /workspaces/*; do [ -d "$d/.git" ] && REPO="$d" && break; done
  fi
  if [ -n "$REPO" ]; then
    cd "$REPO"
    gh release delete "$RELEASE_TAG" -y --cleanup-tag >/dev/null 2>&1 || true
    if gh release create "$RELEASE_TAG" "$APK_OUT" \
      --title "$RELEASE_TITLE" \
      --notes "실전 BETA APK

- Livescore 실제 MLB/KBO/NPB 경기표 수집
- 경기전 상태만 분석
- 경기 시작 후 LIVE 데이터 분석 차단
- 경기 전 🔵 확정픽 로컬 잠금/표시
- MLB 단독 조합
- KBO + NPB 동일/혼합 조합
- 소액 다폴더 후보
- 데이터 오류 시 자동 PASS
- 배당은 분석에 미사용"; then OK=1; fi
  fi
fi

echo ""
echo "================================================"
echo "APK 빌드 완료: $APK_OUT"
if [ "$OK" -eq 1 ]; then
 echo "Release 완료: GitHub → Releases → $RELEASE_TAG"
 echo "→ 퓨어야구분석기_V1.5_실전BETA.apk"
else
 echo "Release 자동 업로드 실패/건너뜀. APK는 ~/workspace 에 있습니다."
fi
echo "================================================"
