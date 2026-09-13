#!/usr/bin/env python3
"""Synthetic v0.56.0 contract samples. No production data or credentials."""
import json, pathlib, datetime
out = pathlib.Path(__file__).resolve().parents[1] / 'Tests/MonitorCoreTests/Fixtures'
now = datetime.datetime(2026, 9, 13, 4, 0, tzinfo=datetime.timezone.utc)
def iso(d): return d.isoformat().replace('+00:00', 'Z')
def usage(n, c=2):
    return dict(totalTokens=n, costUsd=c, cacheReadTokens=n*.7, outputTokens=n*.1,
        timedTokens=n, timedOutputTokens=n*.1,timedDurationMs=10000,
        capabilities=dict(tokenComponents=True,throughput=True),
        clients=dict(codex=n*.8,claude=n*.2),clientCosts=dict(codex=c*.8,claude=c*.2),
        clientCacheReads=dict(codex=n*.6),clientOutputs=dict(codex=n*.08),
        models={'gpt-example':n*.8,'unknown-model':n*.2},modelCosts={'gpt-example':c*.8,'unknown-model':c*.2},
        clientModels={'codex':{'gpt-example':n*.8},'claude':{'unknown-model':n*.2}},
        clientModelCosts={'codex':{'gpt-example':c*.8},'claude':{'unknown-model':c*.2}})
def periods(n): return {k:usage(n*m,2*m) for k,m in [('today',1),('month',10),('allTime',50)]}
def device(name,n,stale=False):
    return dict(deviceId=name,hostname=name,osName='macOS',osVersion='26.0',agentVersion='0.56.0',
        receivedAt=iso(now-datetime.timedelta(minutes=20 if stale else 0)),updatedAt=iso(now),
        stale=stale,trackedClients=['codex','claude'],syncUploadIntervalMs=30000,
        periods=periods(n),periodWindows={'timeZone':'Asia/Shanghai','futureMetadata':42,'today':{'endsAt':'2026-09-14T00:00:00Z'},'month':{'endsAt':'2026-10-01T00:00:00Z'}})
stats=dict(updatedAt=iso(now),periods=periods(125000),devices=[device('Mac-Hub',100000),device('Travel-Mac',25000,True)],
    staleAfterMs=600000,historyRevision='synthetic-v1',deviceHistoryRevision='synthetic-device-v1',
    account={'email':'must-not-be-cached@example.invalid'},futureField='ignored')
history={'daily':[], 'monthly':[]}
for i in range(30):
    if i%6==0: continue
    d=now-datetime.timedelta(days=i);n=(i%7)*5000
    history['daily'].append(dict(date=d.strftime('%Y-%m-%d'),tokens=n,cost=n*.00002,perClient={'codex':dict(tokens=n*.8,cost=n*.000016)}))
for i in range(9):
    d=now.replace(month=9-i);n=(i+1)*50000
    history['monthly'].append(dict(month=d.strftime('%Y-%m'),tokens=n,cost=n*.00002,perClient={'codex':dict(tokens=n*.8,cost=n*.000016)}))
for name,obj in [('stats',stats),('history',history),('health',dict(ok=True,role='hub',runtime='node-hub',version=1,hubBuild=dict(schemaVersion=1,coreRevision=3,coreBuildId='synthetic')) )]:
    (out/(name+'.json')).write_text(json.dumps(obj,ensure_ascii=False,indent=2)+'\n')
