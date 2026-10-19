import sherpa_onnx, json, sys, numpy as np
M='<models>/'  # sherpa-onnx Piper models (see README)
EMB='<campplus.onnx>'
de=["Wie wird das Wetter morgen in Berlin.","Stell bitte einen Timer auf zehn Minuten.","Schalte das Licht im Wohnzimmer aus.","Setze Milch und Brot auf die Einkaufsliste.","Spiel etwas ruhige Musik zum Einschlafen.","Was steht heute in meinem Kalender.","Erinnere mich um sieben Uhr an die Tabletten.","Wie spät ist es gerade in Tokio.","Ruf bitte meine Schwester an.","Wecke mich morgen früh um halb sieben.","Wie lange fährt man von Köln nach Hamburg.","Mach die Heizung im Flur etwas wärmer."]
en=["What is the weather going to be like tomorrow.","Please set a timer for ten minutes.","Turn off the light in the living room.","Add milk and bread to the shopping list.","Play some quiet music for the evening.","What is on my calendar today.","Remind me at seven to take my pills.","What time is it right now in Tokyo.","Please call my sister for me.","Wake me up tomorrow at half past six.","How long does the drive from Boston take.","Make the heating in the hallway a bit warmer."]
voices={'thorsten':('vits-piper-de_DE-thorsten-high-int8','de_DE-thorsten-high.onnx',de),
'kerstin':('vits-piper-de_DE-kerstin-low-int8','de_DE-kerstin-low.onnx',de),
'ljspeech':('vits-piper-en_US-ljspeech-medium-int8','en_US-ljspeech-medium.onnx',en)}
ex=sherpa_onnx.SpeakerEmbeddingExtractor(sherpa_onnx.SpeakerEmbeddingExtractorConfig(model=EMB,num_threads=2,debug=False,provider='cpu'))
out={'dim':ex.dim,'voices':{}}
for name,(d,f,sents) in voices.items():
    tts=sherpa_onnx.OfflineTts(sherpa_onnx.OfflineTtsConfig(model=sherpa_onnx.OfflineTtsModelConfig(vits=sherpa_onnx.OfflineTtsVitsModelConfig(model=M+d+'/'+f,tokens=M+d+'/tokens.txt',data_dir=M+d+'/espeak-ng-data'),num_threads=2)))
    embs=[]
    for i,s in enumerate(sents):
        a=tts.generate(s,sid=0,speed=[1.0,0.95,1.05][i%3])
        st=ex.create_stream(); st.accept_waveform(a.sample_rate,np.array(a.samples,dtype=np.float32)); st.input_finished()
        e=ex.compute(st); embs.append({'sec':round(len(a.samples)/a.sample_rate,2),'v':[round(float(x),5) for x in e]})
    out['voices'][name]=embs
json.dump(out,open(sys.argv[1],'w'))
def cos(a,b): a=np.array(a);b=np.array(b);return float(a@b/np.linalg.norm(a)/np.linalg.norm(b))
V={k:[np.array(e['v']) for e in v] for k,v in out['voices'].items()}
for k,v in V.items():
    m=np.mean(v[:8],0)
    print(k,'self',[round(cos(m,x),2) for x in v[8:]],'loo',[round(cos(np.mean([y for j,y in enumerate(v[:8]) if j!=i],0),v[i]),2) for i in range(8)])
    for k2,v2 in V.items():
        if k2!=k: print('  vs',k2,[round(cos(m,x),2) for x in v2[8:]])
