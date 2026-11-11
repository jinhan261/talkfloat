import SwiftUI
import AppKit
import SayloriCore

struct ConnectionSettings:View {
    @ObservedObject var model:SessionModel
    @ObservedObject var access:CredentialSession
    @State private var remember=false
    @FocusState private var focus:String?
    var body:some View {
        VStack(alignment:.leading,spacing:16){
            HStack{
                VStack(alignment:.leading,spacing:4){
                    Text("豆包同声传译").font(.system(size:13,weight:.medium))
                    Text("所选音频发送至豆包进行翻译").font(.system(size:11)).foregroundStyle(.secondary)
                }
                Spacer()
                Text(model.configured ? "已配置":"未配置").font(.system(size:11)).foregroundStyle(.secondary)
            }
            VStack(alignment:.leading,spacing:12){
                ChoiceStrip(title:"凭据类型",options:[(true,"App ID / Token"),(false,"API Key")],selection:$access.draft.legacy)
                if access.draft.legacy{
                    field("App ID",id:"id"){TextField("输入 App ID",text:$access.draft.appID).focused($focus,equals:"id")}
                    field("Access Token",id:"token"){SecureField("输入 Access Token",text:$access.draft.accessToken).focused($focus,equals:"token")}
                }else{field("API Key",id:"key"){SecureField("输入 API Key",text:$access.draft.apiKey).focused($focus,equals:"key")}}
                Toggle("保存到 macOS 钥匙串",isOn:$remember).toggleStyle(.checkbox).font(.system(size:11))
                Button{Task{await model.applyCredentials(remember:remember)}}label:{
                    HStack(spacing:7){if model.connectionChecking{ProgressView().controlSize(.small)};Text(model.connectionChecking ? "正在检查…":(remember ? "保存并检查":"检查连接"))}.frame(maxWidth:.infinity)
                }.buttonStyle(PanelActionStyle(primary:true)).disabled(model.active || !access.draft.trimmed.isValid)
                Text(remember ? "保存到本机钥匙串。检查连接不上传声音。":"仅本次使用，不修改已存凭据。检查连接不上传声音。")
                    .font(.system(size:11)).lineSpacing(2).foregroundStyle(.secondary).fixedSize(horizontal:false,vertical:true)
            }.padding(12).modifier(CardSurface())
            if !model.connectionResult.isEmpty{Text(model.connectionResult).font(.system(size:11)).fixedSize(horizontal:false,vertical:true).textSelection(.enabled)}
            if !access.message.isEmpty{Text(access.message).font(.system(size:11)).foregroundStyle(.secondary).fixedSize(horizontal:false,vertical:true)}
            HStack{
                Button(access.working ? "正在读取…":"读取已存凭据"){Task{await access.load(interactive:true)}}.disabled(access.working || model.active)
                Spacer()
                Link("豆包控制台 ↗",destination:URL(string:"https://console.volcengine.com/speech/service/10030")!)
            }.buttonStyle(.plain).font(.system(size:11)).foregroundStyle(Brand.accent)
            Text("中英文字保存在这台 Mac。即时预览可能会校正，会议记录以最终译文为准。")
                .font(.system(size:11)).lineSpacing(2).foregroundStyle(.secondary).fixedSize(horizontal:false,vertical:true)
        }.onDisappear{focus=nil}
    }
    private func field<V:View>(_ title:String,id:String,@ViewBuilder content:()->V)->some View {
        VStack(alignment:.leading,spacing:6){
            Text(title).font(.system(size:11,weight:.medium)).foregroundStyle(.secondary)
            content().textFieldStyle(.plain).font(.system(size:12)).padding(.horizontal,10).frame(height:34)
                .background(Brand.field,in:RoundedRectangle(cornerRadius:7))
                .overlay(RoundedRectangle(cornerRadius:7).strokeBorder(focus==id ? Brand.accent:Brand.border,lineWidth:focus==id ? 1.5:0.5))
                .accessibilityLabel(title)
        }
    }
}
