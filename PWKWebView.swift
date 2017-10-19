//
//  PWKWebView.swift
//  CMBMobile
//
//  Created by 罗文兴 on 10/19/17.
//  Copyright © 2017 Yst－WHB. All rights reserved.
//

import Foundation
import WebKit

class PWKWebView:WKWebView {
    
    override init(frame: CGRect, configuration: WKWebViewConfiguration) {
        super.init(frame: frame, configuration: configuration)
    }
    
    required init?(coder: NSCoder) {
        super.init(coder: coder)
    }
    
    override func load(_ request: URLRequest) -> WKNavigation? {
        let req = self.syncCookies(request)
        self.requestInCaseOf302SetCookie(req, complete: {
            newRequest,resp,data in
            DispatchQueue.main.async {
                if let Data = data,let Resp = resp {
                    // load data directly for 200 response
                    if #available(iOS 9.0, *) {
                        self.syncCookiesInJS()
                        let _ = self.webViewLoad(data: Data, resp: Resp)
                    } else {
                        // load request again instead of calling loadHTMLString in case of css/js not working
                        let req = self.syncCookies(newRequest)
                        let _ = super.load(req)
                    }
                } else {
                    let req = self.syncCookies(newRequest)
                    let _ = super.load(req)
                }
            }
        }) {
            _ in
            // let WKWebView handle the network error (go through delegate)
            let _ = super.load(req)
        }
        return nil
    }
    
    // sync cookies by js using document.cookie
    func syncCookiesInJS() {
        if let cookies = HTTPCookieStorage.shared.cookies {
            let script = getJSCookiesString(cookies)
            let cookieScript = WKUserScript(source: script, injectionTime: .atDocumentStart, forMainFrameOnly: false)
            self.configuration.userContentController.addUserScript(cookieScript)
        }
    }
    
    // sync HTTPCookieStorage cookies to URLRequest
    fileprivate func syncCookies(_ req:URLRequest) -> URLRequest {
        var request = req
        if let cookies = HTTPCookieStorage.shared.cookies {
            let dictCookies = HTTPCookie.requestHeaderFields(with: cookies)
            if let cookieStr = dictCookies["Cookie"] {
                request.addValue(cookieStr, forHTTPHeaderField: "Cookie")
            }
        }
        return request
    }
    
    // composite document.cookie
    fileprivate func getJSCookiesString(_ cookies: [HTTPCookie]) -> String {
        var result = ""
        let dateFormatter = DateFormatter()
        dateFormatter.timeZone = TimeZone(abbreviation: "UTC")
        dateFormatter.dateFormat = "EEE, d MMM yyyy HH:mm:ss zzz"
        
        for cookie in cookies {
            result += "document.cookie='\(cookie.name)=\(cookie.value); domain=\(cookie.domain); path=\(cookie.path); "
            if let date = cookie.expiresDate {
                result += "expires=\(dateFormatter.string(from: date)); "
            }
            if (cookie.isSecure) {
                result += "secure; "
            }
            result += "'; "
        }
        return result
    }
    
    @available(iOS 9.0, *)
    fileprivate func webViewLoad(data:Data,resp:URLResponse) -> WKNavigation! {
        guard let url = resp.url else {
            return nil
        }
        let encode = resp.textEncodingName ?? "utf8"
        let mine = resp.mimeType ?? "text/html"
        return self.load(data, mimeType: mine, characterEncodingName: encode, baseURL: url)
    }
}

extension PWKWebView:URLSessionTaskDelegate {
    
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) {
        // set to manual redirect
        completionHandler(nil)
    }
    
    fileprivate func requestInCaseOf302SetCookie (_ request:URLRequest,complete:@escaping (URLRequest,HTTPURLResponse?,Data?) -> Void,failure:@escaping () -> Void ) {
        self.evaluateJavaScript("navigator.userAgent") {
            ua,_ in
            var req = request
            let userAgent = (ua as? String) ?? "iphone"
            let sessionConfig = URLSessionConfiguration.default
            let session = URLSession(configuration: sessionConfig, delegate: self, delegateQueue: nil)
            req.addValue(userAgent, forHTTPHeaderField: "User-Agent")
            let task = session.dataTask(with: req) {
                data,response,error in
                if let _ = error {
                    failure()
                } else {
                    if let resp = response as? HTTPURLResponse {
                        let code = resp.statusCode
                        if code == 200 {
                            // for code 200 return data to load data directly
                            complete(request,resp,data)
                        } else if code >= 300 && code <  400  {
                            // for redirect get location in header,and make a new URLRequest
                            guard let location = resp.allHeaderFields["Location"] as? String,let redirectURL = URL(string: location) else {
                                failure()
                                return
                            }
                            
                            /* no need for achieve Set-Cookie header because URLSession do it automatically
                             if you worry about it uncommit the line */
                            // self.syncCookies(response)
                            
                            let request = URLRequest(url: redirectURL, cachePolicy: .reloadIgnoringLocalAndRemoteCacheData, timeoutInterval: 5)
                            complete(request, nil, nil)
                        }
                    }
                }
            }
            task.resume()
        }
    }
    
    private func syncCookies(response:HTTPURLResponse) {
        if let headers = response.allHeaderFields as? [String:String],let url = response.url {
            let cookies = HTTPCookie.cookies(withResponseHeaderFields:headers, for:url)
            for cookie in cookies {
                HTTPCookieStorage.shared.setCookie(cookie)
            }
        }
    }
    
}
