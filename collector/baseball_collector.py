import json, re, os, datetime, urllib.request
from html import unescape
from collections import defaultdict, deque

KST = datetime.timezone(datetime.timedelta(hours=9))
NOW = datetime.datetime.now(KST)
TODAY = NOW.date()
SEASON = TODAY.year

HEADERS = {
    "User-Agent":"Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 Chrome/140 Safari/537.36",
    "Accept-Language":"ko-KR,ko;q=0.9,en;q=0.8",
    "Accept":"text/html,application/xhtml+xml,application/json;q=0.9,*/*;q=0.8",
}

def get(url, timeout=18):
    req=urllib.request.Request(url,headers=HEADERS)
    with urllib.request.urlopen(req,timeout=timeout) as r:
        return r.read().decode("utf-8","ignore")

def get_json(url): return json.loads(get(url))
def clean_html(x):
    x=re.sub(r"<script.*?</script>"," ",x,flags=re.S|re.I)
    x=re.sub(r"<style.*?</style>"," ",x,flags=re.S|re.I)
    x=re.sub(r"<[^>]+>"," ",x)
    return re.sub(r"\s+"," ",unescape(x)).strip()

def kst_time(iso):
    try:
        d=datetime.datetime.fromisoformat(iso.replace("Z","+00:00")).astimezone(KST)
        return d.strftime("%H:%M"), d.isoformat()
    except: return "",iso

def recpct(w,l):
    try:
        w=int(w);l=int(l);return round(w/(w+l),4) if w+l else .5
    except:return .5

def mlb_today():
    date=TODAY.strftime("%Y-%m-%d")
    url=f"https://statsapi.mlb.com/api/v1/schedule?sportId=1&date={date}&hydrate=probablePitcher,team"
    data=get_json(url); games=[]
    for d in data.get("dates",[]):
        for g in d.get("games",[]):
            st=(g.get("status") or {}).get("abstractGameState","")
            tm,iso=kst_time(g.get("gameDate",""))
            away=(g.get("teams") or {}).get("away",{})
            home=(g.get("teams") or {}).get("home",{})
            ap=(away.get("probablePitcher") or {}).get("fullName","")
            hp=(home.get("probablePitcher") or {}).get("fullName","")
            games.append({
                "source":"MLB StatsAPI","league":"MLB","gamePk":str(g.get("gamePk","")),
                "timeKST":tm,"startISO":iso,
                "status":"경기전" if st=="Preview" else ("종료" if st=="Final" else "경기중"),
                "away":(away.get("team") or {}).get("name",""),
                "home":(home.get("team") or {}).get("name",""),
                "awayWins":away.get("leagueRecord",{}).get("wins"),
                "awayLosses":away.get("leagueRecord",{}).get("losses"),
                "homeWins":home.get("leagueRecord",{}).get("wins"),
                "homeLosses":home.get("leagueRecord",{}).get("losses"),
                "awayWinPct":recpct(away.get("leagueRecord",{}).get("wins",0),away.get("leagueRecord",{}).get("losses",0)),
                "homeWinPct":recpct(home.get("leagueRecord",{}).get("wins",0),home.get("leagueRecord",{}).get("losses",0)),
                "awayStarter":ap,"homeStarter":hp,
                "awayStarterStatus":"확인완료" if ap else "미확인",
                "homeStarterStatus":"확인완료" if hp else "미확인"
            })
    return games

def kbo_today():
    games=[]
    ds=TODAY.strftime("%Y%m%d")
    urls=[f"https://eng.koreabaseball.com/Schedule/Scoreboard.aspx?gameDate={ds}",
          "https://eng.koreabaseball.com/Schedule/Scoreboard.aspx"]
    html=""
    for u in urls:
        try:
            html=get(u)
            if len(html)>1000: break
        except: pass
    if not html:return games
    text=clean_html(html)
    teams=["LG","HANWHA","KIA","SAMSUNG","LOTTE","DOOSAN","KT","SSG","NC","KIWOOM"]
    pat=re.compile(r"(\d{1,2}:\d{2}).{0,130}?("+"|".join(teams)+r").{0,100}?("+"|".join(teams)+r")",re.I)
    seen=set()
    for m in pat.finditer(text):
        a,b=m.group(2).upper(),m.group(3).upper()
        if a==b:continue
        key=m.group(1)+"|"+a+"|"+b
        if key in seen:continue
        seen.add(key)
        # Official English scoreboard may or may not expose starter names pregame.
        # We only mark confirmed when a starter-like "Starting Pitcher" label is actually found near this block.
        block=text[max(0,m.start()-150):min(len(text),m.end()+300)]
        sp=re.findall(r"(?:Starting Pitcher|Pitcher)\s*[:\-]?\s*([A-Za-z .'-]{3,35})",block,re.I)
        ap=sp[0].strip() if len(sp)>0 else ""
        hp=sp[1].strip() if len(sp)>1 else ""
        games.append({
            "source":"KBO Official","league":"KBO","gamePk":key,
            "timeKST":m.group(1),"startISO":"","status":"경기전",
            "away":a,"home":b,"awayWins":None,"awayLosses":None,"homeWins":None,"homeLosses":None,
            "awayWinPct":.5,"homeWinPct":.5,
            "awayStarter":ap,"homeStarter":hp,
            "awayStarterStatus":"확인완료" if ap else "미확인",
            "homeStarterStatus":"확인완료" if hp else "미확인"
        })
    return games

def npb_today():
    # NPB official announced-starter page is the primary source because it directly lists both starters + time.
    games=[]
    urls=["https://npb.jp/announcement/starter/","https://npb.jp/games/"]
    html=""
    src=""
    for u in urls:
        try:
            html=get(u)
            if len(html)>1000:
                src=u;break
        except: pass
    if not html:return games
    text=clean_html(html)

    # Match official Japanese team names + starter names around stadium/time.
    team_names=[
      "読売ジャイアンツ","横浜DeNAベイスターズ","東京ヤクルトスワローズ","阪神タイガース",
      "広島東洋カープ","中日ドラゴンズ","北海道日本ハムファイターズ","千葉ロッテマリーンズ",
      "東北楽天ゴールデンイーグルス","福岡ソフトバンクホークス","埼玉西武ライオンズ","オリックス・バファローズ"
    ]
    short={
      "読売ジャイアンツ":"요미우리","横浜DeNAベイスターズ":"DeNA","東京ヤクルトスワローズ":"야쿠르트",
      "阪神タイガース":"한신","広島東洋カープ":"히로시마","中日ドラゴンズ":"주니치",
      "北海道日本ハムファイターズ":"니혼햄","千葉ロッテマリーンズ":"지바롯데",
      "東北楽天ゴールデンイーグルス":"라쿠텐","福岡ソフトバンクホークス":"소프트뱅크",
      "埼玉西武ライオンズ":"세이부","オリックス・バファローズ":"오릭스"
    }
    # Official page usually appears as: Team Starter / Team Starter / (stadium) 18:00
    # Split around times and search backwards for two team names and text between them.
    for tm in re.finditer(r"(\d{1,2}:\d{2})",text):
        block=text[max(0,tm.start()-260):tm.end()+20]
        found=[]
        for name in team_names:
            pos=block.rfind(name)
            if pos>=0: found.append((pos,name))
        found=sorted(found)[-2:]
        if len(found)<2:continue
        (p1,t1),(p2,t2)=found
        if t1==t2:continue
        s1=block[p1+len(t1):p2].strip()
        s2=block[p2+len(t2):]
        s2=re.sub(r"[（(].*?$","",s2).strip()
        # trim labels/noise; starter names are the nearest short text after team name
        s1=re.sub(r"\s+"," ",s1)[:40].strip(" ・|")
        s2=re.sub(r"\s+"," ",s2)[:40].strip(" ・|")
        key=tm.group(1)+"|"+t1+"|"+t2
        if any(g["gamePk"]==key for g in games):continue
        games.append({
            "source":"NPB Official Starter" if "starter" in src else "NPB Official",
            "league":"NPB","gamePk":key,"timeKST":tm.group(1),"startISO":"","status":"경기전",
            "away":short.get(t1,t1),"home":short.get(t2,t2),
            "awayWins":None,"awayLosses":None,"homeWins":None,"homeLosses":None,
            "awayWinPct":.5,"homeWinPct":.5,
            "awayStarter":s1,"homeStarter":s2,
            "awayStarterStatus":"확인완료" if s1 else "미확인",
            "homeStarterStatus":"확인완료" if s2 else "미확인"
        })
    return games

def mlb_first_inning_history(days=120):
    # Official MLB linescore backfill. One request per date; only completed games are used.
    start=TODAY-datetime.timedelta(days=days)
    raw=[]
    d=start
    while d<TODAY:
        ds=d.strftime("%Y-%m-%d")
        try:
            url=f"https://statsapi.mlb.com/api/v1/schedule?sportId=1&date={ds}&hydrate=linescore"
            data=get_json(url)
            for day in data.get("dates",[]):
                for g in day.get("games",[]):
                    if (g.get("status") or {}).get("abstractGameState")!="Final":continue
                    teams=g.get("teams") or {}
                    away=(teams.get("away") or {}).get("team",{}).get("name","")
                    home=(teams.get("home") or {}).get("team",{}).get("name","")
                    innings=(g.get("linescore") or {}).get("innings") or []
                    if not innings:continue
                    inn1=innings[0]
                    ar=(inn1.get("away") or {}).get("runs")
                    hr=(inn1.get("home") or {}).get("runs")
                    if ar is None or hr is None:continue
                    raw.append({"date":ds,"away":away,"home":home,"awayR1":int(ar),"homeR1":int(hr)})
        except: pass
        d+=datetime.timedelta(days=1)
    return raw

def backtest_first_inning(raw, window=20, min_games=10):
    # Strict rolling evaluation: only PRIOR games for each team are used.
    score_hist=defaultdict(lambda:deque(maxlen=window))
    allow_hist=defaultdict(lambda:deque(maxlen=window))
    total=correct=passed=0
    yrfi_n=yrfi_c=nrfi_n=nrfi_c=0
    for g in raw:
        a,h=g["away"],g["home"]
        if len(score_hist[a])>=min_games and len(score_hist[h])>=min_games and len(allow_hist[a])>=min_games and len(allow_hist[h])>=min_games:
            a_score=sum(score_hist[a])/len(score_hist[a])
            h_score=sum(score_hist[h])/len(score_hist[h])
            a_allow=sum(allow_hist[a])/len(allow_hist[a])
            h_allow=sum(allow_hist[h])/len(allow_hist[h])
            p_a=(a_score+h_allow)/2
            p_h=(h_score+a_allow)/2
            p_yrfi=1-(1-p_a)*(1-p_h)
            pred=None
            if p_yrfi>=0.58: pred="YRFI"
            elif p_yrfi<=0.42: pred="NRFI"
            if pred:
                passed+=1
                actual="YRFI" if g["awayR1"]+g["homeR1"]>0 else "NRFI"
                if pred=="YRFI": yrfi_n+=1
                else:nrfi_n+=1
                if pred==actual:
                    correct+=1
                    if pred=="YRFI":yrfi_c+=1
                    else:nrfi_c+=1
        total+=1
        # update AFTER prediction => no future leakage
        score_hist[a].append(1 if g["awayR1"]>0 else 0)
        allow_hist[a].append(1 if g["homeR1"]>0 else 0)
        score_hist[h].append(1 if g["homeR1"]>0 else 0)
        allow_hist[h].append(1 if g["awayR1"]>0 else 0)

    return {
      "rawGames":total,"evaluatedPicks":passed,"correct":correct,
      "accuracy":round(correct/passed*100,2) if passed else None,
      "coverage":round(passed/total*100,2) if total else 0,
      "YRFI":{"picks":yrfi_n,"correct":yrfi_c,"accuracy":round(yrfi_c/yrfi_n*100,2) if yrfi_n else None},
      "NRFI":{"picks":nrfi_n,"correct":nrfi_c,"accuracy":round(nrfi_c/nrfi_n*100,2) if nrfi_n else None},
      "window":window,"minGames":min_games,"thresholds":{"YRFI":0.58,"NRFI":0.42},
      "note":"각 경기 예측 시 해당 경기 이전 기록만 사용. 미래누설 없음."
    }

def team_first_inning_rates(raw, last_n=30):
    by=defaultdict(list)
    for g in raw:
        by[g["away"]].append((1 if g["awayR1"]>0 else 0,1 if g["homeR1"]>0 else 0))
        by[g["home"]].append((1 if g["homeR1"]>0 else 0,1 if g["awayR1"]>0 else 0))
    out={}
    for team,x in by.items():
        x=x[-last_n:]
        if not x:continue
        out[team]={
          "games":len(x),
          "scored1stPct":round(sum(v[0] for v in x)/len(x)*100,1),
          "allowed1stPct":round(sum(v[1] for v in x)/len(x)*100,1)
        }
    return out

def livescore_backup():
    try:
        h=get("https://livescore.co.kr/sports/score_board/baseball_score.php")
        return {"ok":True,"bytes":len(h)}
    except Exception as e:return {"ok":False,"error":type(e).__name__+": "+str(e)[:120]}

def main():
    result={"generatedAt":NOW.isoformat(),"dateKST":TODAY.isoformat(),"mode":"PRE_GAME_ONLY",
            "oddsUsedForAnalysis":False,"sources":{},"games":[]}
    for name,fn in [("MLB",mlb_today),("KBO",kbo_today),("NPB",npb_today)]:
        try:
            x=fn();result["games"].extend(x);result["sources"][name]={"ok":True,"games":len(x)}
        except Exception as e:result["sources"][name]={"ok":False,"error":type(e).__name__+": "+str(e)[:160]}
    result["sources"]["LivescoreBackup"]=livescore_backup()

    # Historical 1st inning module (MLB official data)
    try:
        hist=mlb_first_inning_history(120)
        bt=backtest_first_inning(hist,20,10)
        bt["teamRatesLast30"]=team_first_inning_rates(hist,30)
        result["firstInningMLB"]=bt
        result["sources"]["MLBFirstInning"]={"ok":True,"games":len(hist)}
    except Exception as e:
        result["firstInningMLB"]={"error":type(e).__name__+": "+str(e)}
        result["sources"]["MLBFirstInning"]={"ok":False}

    os.makedirs("live",exist_ok=True)
    with open("live/baseball.json","w",encoding="utf-8") as f:
        json.dump(result,f,ensure_ascii=False,indent=2)
    print(json.dumps(result["sources"],ensure_ascii=False))
    print("1회 백테스트:",json.dumps(result.get("firstInningMLB",{}),ensure_ascii=False)[:500])

if __name__=="__main__": main()
