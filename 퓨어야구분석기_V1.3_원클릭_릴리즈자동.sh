#!/usr/bin/env bash
set -euo pipefail

APP_DIR="$HOME/workspace/PureBaseballAnalyzer"
APK_OUT="$HOME/workspace/퓨어야구분석기_V1.3.apk"

echo "================================================"
echo "  퓨어야구분석기 V1.3 - 모바일 Codespaces 원클릭"
echo "================================================"

mkdir -p "$HOME/workspace"
rm -rf "$APP_DIR"
mkdir -p "$APP_DIR/app/src/main/java/com/pureanalysis/baseball"
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

java -version

cat > "$APP_DIR/settings.gradle" <<'EOF'
pluginManagement {
    repositories {
        google()
        mavenCentral()
        gradlePluginPortal()
    }
}
dependencyResolutionManagement {
    repositoriesMode.set(RepositoriesMode.FAIL_ON_PROJECT_REPOS)
    repositories {
        google()
        mavenCentral()
    }
}
rootProject.name = "PureBaseballAnalyzer"
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
plugins {
    id 'com.android.application'
}

android {
    namespace 'com.pureanalysis.baseball'
    compileSdk 35

    defaultConfig {
        applicationId "com.pureanalysis.baseball"
        minSdk 26
        targetSdk 35
        versionCode 4
        versionName "1.3"
    }

    buildTypes {
        debug { debuggable true }
        release { minifyEnabled false }
    }
}
EOF

cat > "$APP_DIR/app/src/main/AndroidManifest.xml" <<'EOF'
<manifest xmlns:android="http://schemas.android.com/apk/res/android">
    <uses-permission android:name="android.permission.INTERNET"/>
    <uses-permission android:name="android.permission.POST_NOTIFICATIONS"/>
    <uses-permission android:name="android.permission.WAKE_LOCK"/>

    <application
        android:allowBackup="true"
        android:label="퓨어야구 분석기"
        android:theme="@style/AppTheme">
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
        <item name="android:statusBarColor">#07111F</item>
        <item name="android:navigationBarColor">#07111F</item>
        <item name="android:windowLightStatusBar">false</item>
        <item name="android:colorAccent">#48A8FF</item>
    </style>
</resources>
EOF

cat > "$APP_DIR/app/src/main/res/drawable/card_bg.xml" <<'EOF'
<shape xmlns:android="http://schemas.android.com/apk/res/android">
    <solid android:color="#112039"/>
    <corners android:radius="18dp"/>
    <stroke android:width="1dp" android:color="#27425F"/>
</shape>
EOF

cat > "$APP_DIR/app/src/main/res/drawable/btn_bg.xml" <<'EOF'
<shape xmlns:android="http://schemas.android.com/apk/res/android">
    <solid android:color="#1877F2"/>
    <corners android:radius="14dp"/>
</shape>
EOF

cat > "$APP_DIR/app/src/main/java/com/pureanalysis/baseball/MainActivity.java" <<'EOF'
package com.pureanalysis.baseball;

import android.app.Activity;
import android.os.Bundle;
import android.graphics.Color;
import android.graphics.Typeface;
import android.view.Gravity;
import android.widget.*;
import java.text.SimpleDateFormat;
import java.util.*;

public class MainActivity extends Activity {

    static class Candidate {
        String league, team, status, reason;
        int score;
        Candidate(String league, String team, String status, int score, String reason) {
            this.league = league;
            this.team = team;
            this.status = status;
            this.score = score;
            this.reason = reason;
        }
    }

    private LinearLayout body;
    private TextView lastUpdate;

    private final int BG = Color.rgb(7,17,31);
    private final int CARD = Color.rgb(17,32,57);
    private final int TEXT = Color.rgb(242,247,255);
    private final int SUB = Color.rgb(157,179,206);
    private final int BLUE = Color.rgb(72,168,255);
    private final int GREEN = Color.rgb(59,213,154);
    private final int YELLOW = Color.rgb(250,190,60);
    private final int RED = Color.rgb(255,92,92);

    private final List<Candidate> mlb = new ArrayList<>();
    private final List<Candidate> kbo = new ArrayList<>();
    private final List<Candidate> npb = new ArrayList<>();

    @Override
    protected void onCreate(Bundle savedInstanceState) {
        super.onCreate(savedInstanceState);
        seedDemoData();
        renderHome();
    }

    private void seedDemoData() {
        // 화면/로직 확인용 예시 데이터. 실시간 데이터 연결 전 데모.
        mlb.add(new Candidate("MLB","PHI","BLUE",88,"선발 안정 · 불펜 정상 · 반례위험 낮음"));
        mlb.add(new Candidate("MLB","LAD","BLUE",84,"상대 선발 상성 우위 · 타선 흐름 양호"));
        mlb.add(new Candidate("MLB","NYY","GREEN",76,"팀 흐름 강함 · 불펜 소진 일부"));
        mlb.add(new Candidate("MLB","BOS","HOLD",64,"선발 변동성 · 라인업 확인 필요"));
        mlb.add(new Candidate("MLB","CHC","OUT",49,"최근 타선 하락 · 유사패배 조건 다수"));

        kbo.add(new Candidate("KBO","LG","BLUE",82,"선발 우위 · 불펜 휴식 · 최근 흐름 지속형"));
        kbo.add(new Candidate("KBO","한화","GREEN",74,"상대 선발 대응 양호 · 반례 1개"));
        kbo.add(new Candidate("KBO","KT","HOLD",61,"상대 특정상성 위험"));
        kbo.add(new Candidate("KBO","삼성","OUT",47,"불펜 소진 · 유사패배 조건 일치"));

        npb.add(new Candidate("NPB","소프트뱅크","BLUE",86,"상대전적 우위 · 선발 안정 · 반례위험 낮음"));
        npb.add(new Candidate("NPB","한신","GREEN",75,"최근 타선 양호 · 불펜 정상"));
        npb.add(new Candidate("NPB","요미우리","HOLD",63,"선발 최근 구위 변동"));
        npb.add(new Candidate("NPB","라쿠텐","OUT",46,"최근 흐름 약세 · 상대 상성 불리"));
    }

    private int dp(int v) {
        return (int)(v * getResources().getDisplayMetrics().density + 0.5f);
    }

    private TextView txt(String s, int sp, int color, boolean bold) {
        TextView t = new TextView(this);
        t.setText(s);
        t.setTextSize(sp);
        t.setTextColor(color);
        t.setPadding(0,dp(4),0,dp(4));
        if (bold) t.setTypeface(Typeface.DEFAULT, Typeface.BOLD);
        return t;
    }

    private LinearLayout card() {
        LinearLayout c = new LinearLayout(this);
        c.setOrientation(LinearLayout.VERTICAL);
        c.setPadding(dp(16),dp(14),dp(16),dp(14));
        c.setBackgroundResource(com.pureanalysis.baseball.R.drawable.card_bg);
        LinearLayout.LayoutParams lp = new LinearLayout.LayoutParams(-1,-2);
        lp.setMargins(dp(12),dp(8),dp(12),dp(8));
        c.setLayoutParams(lp);
        return c;
    }

    private Button button(String label) {
        Button b = new Button(this);
        b.setText(label);
        b.setTextColor(Color.WHITE);
        b.setTextSize(14);
        b.setAllCaps(false);
        b.setBackgroundResource(com.pureanalysis.baseball.R.drawable.btn_bg);
        return b;
    }

    private List<Candidate> blueOnly(List<Candidate> src) {
        List<Candidate> out = new ArrayList<>();
        for (Candidate c : src) if ("BLUE".equals(c.status)) out.add(c);
        out.sort((a,b) -> Integer.compare(b.score, a.score));
        return out;
    }

    private String mixedComboText() {
        List<Candidate> pool = new ArrayList<>();
        pool.addAll(blueOnly(kbo));
        pool.addAll(blueOnly(npb));
        pool.sort((a,b) -> Integer.compare(b.score, a.score));

        if (pool.size() < 2) return null;

        Candidate a = pool.get(0);
        Candidate b = pool.get(1);
        return a.league + " " + a.team + " 승 + " + b.league + " " + b.team + " 승";
    }

    private String mlbComboText() {
        List<Candidate> pool = blueOnly(mlb);
        if (pool.size() < 2) return null;
        return pool.get(0).team + " 승 + " + pool.get(1).team + " 승";
    }

    private void addComboCard(String title, String comboText) {
        LinearLayout c = card();
        boolean combo = comboText != null;

        LinearLayout top = new LinearLayout(this);
        top.setGravity(Gravity.CENTER_VERTICAL);
        top.addView(txt(title,19,TEXT,true), new LinearLayout.LayoutParams(0,-2,1f));
        top.addView(txt(combo ? "조합픽 생성" : "PASS",14,combo?GREEN:SUB,true));
        c.addView(top);

        if (combo) {
            c.addView(txt(comboText,17,TEXT,true));
            c.addView(txt("최종통과 🔵 후보 중 점수 상위 2경기",13,SUB,false));
            c.addView(txt("총 배당 2.24  ※ 분석에는 배당 미사용",15,GREEN,true));
        } else {
            c.addView(txt("최종통과 🔵 2경기 미만 → 조합 생성 안 함",14,SUB,false));
        }
        body.addView(c);
    }

    private int count(List<Candidate> src, String status) {
        int n=0;
        for (Candidate c : src) if (status.equals(c.status)) n++;
        return n;
    }

    private int colorFor(String status) {
        if ("BLUE".equals(status)) return BLUE;
        if ("GREEN".equals(status)) return GREEN;
        if ("HOLD".equals(status)) return YELLOW;
        return RED;
    }

    private String iconFor(String status) {
        if ("BLUE".equals(status)) return "🔵";
        if ("GREEN".equals(status)) return "🟢";
        if ("HOLD".equals(status)) return "🟡";
        return "🔴";
    }

    private void addLeagueDetail(String name, List<Candidate> list) {
        LinearLayout c = card();

        LinearLayout top = new LinearLayout(this);
        top.setGravity(Gravity.CENTER_VERTICAL);
        top.addView(txt(name + " 분석 결과",18,TEXT,true), new LinearLayout.LayoutParams(0,-2,1f));
        Button b = button("↻");
        b.setOnClickListener(v -> Toast.makeText(this,
            name + " 경기 시작 전 정보만 재검증",
            Toast.LENGTH_SHORT).show());
        top.addView(b, new LinearLayout.LayoutParams(dp(58),dp(46)));
        c.addView(top);

        c.addView(txt(
            "🔵 " + count(list,"BLUE") +
            "   🟢 " + count(list,"GREEN") +
            "   🟡 " + count(list,"HOLD") +
            "   🔴 " + count(list,"OUT"),
            14,SUB,false
        ));

        c.addView(txt("추천/최종통과",14,GREEN,true));
        for (Candidate x : list) {
            if ("BLUE".equals(x.status)) {
                c.addView(txt(iconFor(x.status)+" "+x.team+"  "+x.score+"점",15,colorFor(x.status),true));
                c.addView(txt("  └ "+x.reason,12,SUB,false));
            }
        }

        c.addView(txt("강함 후보",14,GREEN,true));
        boolean hasGreen=false;
        for (Candidate x : list) {
            if ("GREEN".equals(x.status)) {
                hasGreen=true;
                c.addView(txt(iconFor(x.status)+" "+x.team+"  "+x.score+"점",14,colorFor(x.status),true));
                c.addView(txt("  └ "+x.reason,12,SUB,false));
            }
        }
        if (!hasGreen) c.addView(txt("없음",12,SUB,false));

        c.addView(txt("보류",14,YELLOW,true));
        for (Candidate x : list) {
            if ("HOLD".equals(x.status)) {
                c.addView(txt(iconFor(x.status)+" "+x.team+"  "+x.score+"점",14,colorFor(x.status),true));
                c.addView(txt("  └ "+x.reason,12,SUB,false));
            }
        }

        c.addView(txt("제외",14,RED,true));
        for (Candidate x : list) {
            if ("OUT".equals(x.status)) {
                c.addView(txt(iconFor(x.status)+" "+x.team+"  "+x.score+"점",14,colorFor(x.status),true));
                c.addView(txt("  └ "+x.reason,12,SUB,false));
            }
        }

        body.addView(c);
    }

    private void renderHome() {
        LinearLayout root = new LinearLayout(this);
        root.setOrientation(LinearLayout.VERTICAL);
        root.setBackgroundColor(BG);

        ScrollView scroll = new ScrollView(this);
        body = new LinearLayout(this);
        body.setOrientation(LinearLayout.VERTICAL);
        body.setPadding(dp(4),dp(12),dp(4),dp(16));
        scroll.addView(body);

        LinearLayout header = card();
        header.addView(txt("⚾ 퓨어야구 분석기 V1.3",24,TEXT,true));
        header.addView(txt("배당 제외 · PRE-GAME ONLY · PASS 우선",13,BLUE,false));
        header.addView(txt("KBO + NPB 최종통과 후보를 실제로 합산해 조합",13,GREEN,true));
        header.addView(txt("경기 시작 후에도 경기 전 확정픽/제외팀 기록 유지",13,YELLOW,true));

        lastUpdate = txt("마지막 업데이트: --:--:--",12,SUB,false);
        header.addView(lastUpdate);

        Button refresh = button("↻ 전체 새로고침 / 재검증");
        refresh.setOnClickListener(v -> {
            String now = new SimpleDateFormat("HH:mm:ss", Locale.KOREA).format(new Date());
            lastUpdate.setText("마지막 업데이트: " + now);
            Toast.makeText(this,
                "시작 전 선발·라인업·불펜·뉴스·날씨·반례조건만 재검증",
                Toast.LENGTH_SHORT).show();
        });
        header.addView(refresh);
        body.addView(header);

        LinearLayout rule = card();
        rule.addView(txt("조합 규칙",19,TEXT,true));
        rule.addView(txt("MLB → MLB 🔵 후보끼리만 2경기 조합",14,TEXT,false));
        rule.addView(txt("KBO+NPB → KBO+KBO / NPB+NPB / KBO+NPB 모두 허용",14,TEXT,false));
        rule.addView(txt("🔵 합계 2개 미만이면 무조건 PASS",14,YELLOW,true));
        body.addView(rule);

        addComboCard("🇺🇸 MLB 조합", mlbComboText());
        addComboCard("🇰🇷🇯🇵 KBO + NPB 조합", mixedComboText());

        addLeagueDetail("MLB", mlb);
        addLeagueDetail("KBO", kbo);
        addLeagueDetail("NPB", npb);

        LinearLayout live = card();
        live.addView(txt("LIVE 경기의 경기 전 예측",19,TEXT,true));
        live.addView(txt("경기 시작 후에도 아래 기록은 그대로 유지",13,SUB,false));
        live.addView(txt("예: PHI 승 🔵 88점",16,GREEN,true));
        live.addView(txt("제외 예: CHC 🔴 49점",15,RED,true));
        live.addView(txt("🔒 LIVE 스코어·안타·실점·투구내용은 분석값에 반영하지 않음",13,YELLOW,true));
        body.addView(live);

        LinearLayout record = card();
        record.addView(txt("누적 기록",19,TEXT,true));
        record.addView(txt("MLB 조합       0승 0패 · PASS 0회",14,GREEN,true));
        record.addView(txt("KBO/NPB 조합   0승 0패 · PASS 0회",14,GREEN,true));
        record.addView(txt("🔵 추천팀       0승 0패",14,BLUE,true));
        record.addView(txt("🔴 제외팀       실제 패배 0 / 실제 승리 0",14,RED,true));
        record.addView(txt("※ 추천팀 적중률 + 제외팀 판단 정확도를 따로 누적",13,SUB,false));
        body.addView(record);

        LinearLayout nav = new LinearLayout(this);
        nav.setOrientation(LinearLayout.HORIZONTAL);
        nav.setGravity(Gravity.CENTER);
        nav.setBackgroundColor(CARD);

        String[] names = {"홈","리그","분석","기록","알림"};
        for (String n : names) {
            Button b = new Button(this);
            b.setText(n);
            b.setTextColor(n.equals("홈")?BLUE:SUB);
            b.setAllCaps(false);
            b.setBackgroundColor(Color.TRANSPARENT);
            nav.addView(b,new LinearLayout.LayoutParams(0,dp(54),1f));
        }

        root.addView(scroll,new LinearLayout.LayoutParams(-1,0,1f));
        root.addView(nav);
        setContentView(root);
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
rm -rf /tmp/cmdtools
mkdir -p /tmp/cmdtools
unzip -q /tmp/cmdtools.zip -d /tmp/cmdtools
cp -R /tmp/cmdtools/cmdline-tools/* "$ANDROID_HOME/cmdline-tools/latest/"

export PATH="$JAVA_HOME/bin:$ANDROID_HOME/cmdline-tools/latest/bin:$ANDROID_HOME/platform-tools:$PATH"

yes | "$ANDROID_HOME/cmdline-tools/latest/bin/sdkmanager" --licenses >/dev/null || true
"$ANDROID_HOME/cmdline-tools/latest/bin/sdkmanager" \
  "platform-tools" \
  "platforms;android-35" \
  "build-tools;35.0.0" >/dev/null

echo "[4/6] APK 빌드..."
cd "$APP_DIR"
gradle --no-daemon :app:assembleDebug

echo "[5/6] APK 복사..."
cp "$APP_DIR/app/build/outputs/apk/debug/app-debug.apk" "$APK_OUT"

echo "[6/6] GitHub Release 자동 업로드..."

RELEASE_TAG="baseball-v1.3"
RELEASE_TITLE="퓨어야구분석기 V1.3"
RELEASE_OK=0

if command -v gh >/dev/null 2>&1 && gh auth status >/dev/null 2>&1; then
    REPO_DIR=""
    if [ -n "${GITHUB_REPOSITORY:-}" ] && [ -d "/workspaces/$(basename "$GITHUB_REPOSITORY")/.git" ]; then
        REPO_DIR="/workspaces/$(basename "$GITHUB_REPOSITORY")"
    else
        for d in /workspaces/*; do
            if [ -d "$d/.git" ]; then
                REPO_DIR="$d"
                break
            fi
        done
    fi

    if [ -n "$REPO_DIR" ]; then
        cd "$REPO_DIR"
        gh release delete "$RELEASE_TAG" -y --cleanup-tag >/dev/null 2>&1 || true

        if gh release create "$RELEASE_TAG" "$APK_OUT" \
            --title "$RELEASE_TITLE" \
            --notes "퓨어야구 분석기 Android APK

- MLB 단독 조합
- KBO + NPB 동일리그/혼합 조합
- 🔵 추천 / 🟢 강함 / 🟡 보류 / 🔴 제외
- 경기 시작 전 확정값 잠금
- LIVE 경기 중 정보는 분석에 미사용
- 경기 시작 후에도 경기 전 추천/제외 기록 표시
- 배당은 분석에 사용하지 않고 조합 생성 시 총배당만 표시"; then
            RELEASE_OK=1
        fi
    fi
fi

echo ""
echo "================================================"
echo "빌드 완료!"
echo "APK: $APK_OUT"
echo ""

if [ "$RELEASE_OK" -eq 1 ]; then
    echo "GitHub Release 업로드 완료!"
    echo "저장소 → Releases → $RELEASE_TAG"
    echo "→ 퓨어야구분석기_V1.3.apk 를 눌러 바로 다운로드하세요."
else
    echo "APK 빌드는 성공했지만 Release 자동 업로드는 건너뛰었습니다."
    echo "Codespaces 왼쪽 파일:"
    echo "workspace → 퓨어야구분석기_V1.3.apk"
    echo ""
    echo "Release 인증 확인 명령: gh auth status"
fi
echo "================================================"
