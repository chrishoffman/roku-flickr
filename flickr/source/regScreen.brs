
Function doRegistration(linkNow=True As Boolean) As Integer

    'screenFacade = CreateObject("roParagraphScreen")
    'screenFacade.show()

    oa = Oauth()
    
    if oa.linked() and checkOauthToken() and linkNow then
        oa.resetHMAC()
        ans=ShowDialog2Buttons("Token invalid", "Unable to authenticate.  This could be a temporary issue or due to revoked access by the user.", "Link Again", "Exit")
        if ans=0 then 
            oa.erase()
        else
            return 2
        end if
    end if

    if not oa.linked() and linkNow
        status = doOauthLink()
        if status<>0 then return status
        showCongratulationsScreen()
    end if

    return 0   

End Function

Function checkOauthToken() As Integer
    print "RegScreen: checkOauthToken"
    
    flickr = LoadFlickr()
    oa = Oauth()

    http = NewHttp(flickr.api_prefix+"?method=flickr.test.login")
    oa.sign(http,true)
    xml=http.getToStringWithTimeout(30)
    if http.status = 200 then
        print xml
        rsp=CreateObject("roXMLElement")
        if not rsp.Parse(xml) then stop
        if rsp@stat="ok" then
            flickr.nsid=rsp.user@id
            flickr.username=rsp.user.username.GetText()
            return 0
        end if
    end if
    
    return 1
End Function

Function doOauthLink() As Integer
    status = doTempLink()
    if status=0
        status = doFlickrEnroll()
        if status=0 then status = doLink()
    end if

    return status
End Function

Function doTempLink() As Integer
    print "RegScreen: doTempLink"
    status = 2

    flickr = LoadFlickr()
    oa = Oauth()

    http = NewHttp(flickr.oauth_prefix+"/request_token")
    http.AddParam("oauth_callback",flickr.link_prefix+"/oauth/callback")
    oa.sign(http,false)
    rsp = http.getToStringWithTimeout(30)

    print "RegScreen: http failure = "; http.Http.GetFailureReason()
    print "RegScreen: temporary registration response = "; rsp

    'temporary token
    params = NewUrlParams(rsp)
    oa.authtoken = params.get("oauth_token")
    oa.authsecret = params.get("oauth_token_secret")

    if isnonemptystr(oa.authtoken) AND isnonemptystr(oa.authsecret) 
        print "temp oauth: "; oa.dump()
        status = 0
    else
        print "RegScreen: failed to retrieve temporary token"
        print "temp oauth: "; oa.dump()
        status = 2
    end if

    return status
End Function

Function doFlickrEnroll() As Integer
    print "RegScreen: doFlickrEnroll"
    status = 1 ' error

    flickr = LoadFlickr()
    oa = Oauth()
    
    regscreen = displayRegistrationScreen()
    
    while true
        sn = CreateObject("roDeviceInfo").GetDeviceUniqueId() 
        regCode = getRegistrationCode(sn)
        
        'if we've failed to get the registration code, bail out, otherwise we'll
        'get rid of the retreiving... text and replace it with the real code       
        if regCode = "" then return 2
        regscreen.SetRegistrationCode(regCode)
        print "Enter registration code " + regCode + " at " + flickr.link_prefix + " for " + sn
        
        duration = 0
        'make an http request to see if the device has been registered on the backend
        while true
            status = checkRegistrationStatus(sn, regCode)
            print itostr(status)
            if status < 3 return status
            
            getNewCode = false
            retryInterval=m.retryInterval
            retryDuration=m.retryDuration
            print "retry duration "; itostr(duration); " at ";  itostr(retryInterval);
            print " sec intervals for "; itostr(retryDuration); " secs max"
          
            'wait for the retry interval to expire or the user to press a button
            'indicating they either want to quit or fetch a new registration code
            while true
                print "Wait for " + itostr(retryInterval)
                msg = wait(retryInterval * 1000, regscreen.GetMessagePort())
                duration = duration + retryInterval
                if msg = invalid exit while
                
                if type(msg) = "roCodeRegistrationScreenEvent"
                    if msg.isScreenClosed()
                        print "Screen closed"
                        return 1
                    elseif msg.isButtonPressed()
                        print "Button pressed: "; msg.GetIndex(); " " msg.GetData()
                        if msg.GetIndex() = 0
                            regscreen.SetRegistrationCode("retrieving code...")
                            getNewCode = true
                            exit while
                        endif
                        if msg.GetIndex() = 1 return 1
                    endif
                endif
            end while
            
            if duration >= retryDuration then
                ans=ShowDialog2Buttons("Request timed out", "Unable to link to Flickr within time limit.", "Try Again", "Back")
                if ans=0 then 
                    regscreen.SetRegistrationCode("retrieving code...")
                    getNewCode = true
                else
                    return 1
                end if
            end if
            
            if getNewCode exit while
            
            print "poll prelink again..."
        end while
    end while

    print "RegScreen: enroll status: "; status
    return status
End Function

Function doLink() As Integer
    print "RegScreen: doLink"
    status = 2

    flickr = LoadFlickr()
    oa = Oauth()
    
    http = NewHttp(flickr.oauth_prefix+"/access_token")
    oa.sign(http,true,true)
    print "RegScreen: access_token URL: "; http.GetUrl()

    rsp = http.getToStringWithTimeout(30)
    print "RegScreen: final registration response = "; rsp

    params = NewUrlParams(rsp)
    oa.authtoken = params.get("oauth_token")
    oa.authsecret = params.get("oauth_token_secret")
    flickr.nsid=params.get("user_nsid")
    flickr.username=params.get("username")
    oa.resetHmac()

    if oa.linked() then
        oa.save()
        print "RegScreen: final oauth: "; oa.dump()
        status = 0
    else
        print "RegScreen: failed to retrieve final authorization token"
    end if

    return status
End Function


'******************************************************
'Load/Save a set of parameters to registry
'These functions must be called from an AA that has
'a "section" string and an "items" list of strings.
'******************************************************
Function loadReg() As Boolean
    for each item in m.items
        temp =  RegRead(item, m.section)
        if temp = invalid then temp = ""
        m[item] = temp
    end for
    return definedReg()
End Function

Function saveReg()
    for each item in m.items
        RegWrite(item, m[item], m.section)
    end for
End Function

Function eraseReg()
    for each item in m.items
        RegDelete(item, m.section)
        m[item] = ""
    end for
End Function

Function definedReg() As Boolean
    for each item in m.items
        if not m.DoesExist(item) then return false
        if Len(m[item])=0 then return false
    end for
    return true
End Function

Function dumpReg() As String
    result = ""
    for each item in m.items
        if m.DoesExist(item) then result = result + " " +item+"="+m[item]
    end for
    return result
End Function

'********************************************************************
'** Fetch the prelink code from the registration service. return
'** valid registration code on success or an empty string on failure
'********************************************************************
Function getRegistrationCode(sn As String) As String
    if sn = "" then return ""
    
    oa = Oauth()
    flickr = LoadFlickr()
    
    http = NewHttp(flickr.link_prefix+"/getRegCode?partner=roku&service=flickr&deviceTypeName=roku&deviceID="+sn+"&oauth_token="+oa.authtoken)
    print "RegScreen: access_token URL: "; http.GetUrl()

    rsp = http.getToStringWithTimeout(30)
    
    xml=ParseXML(rsp)
    print "GOT: " + rsp
    print "Reason: " + http.Http.GetFailureReason()
    
    if xml=invalid then
        print "Can't parse getRegistrationCode response"
        ShowConnectionFailed()
        return ""
    endif
    
    if xml.GetName() <> "result"
        Dbg("Bad register response: ",  xml.GetName())
        ShowConnectionFailed()
        return ""
    endif
    
    if islist(xml.GetBody()) = false then
        Dbg("No registration information available")
        ShowConnectionFailed()
        return ""
    endif

    'default values for retry logic
    retryInterval = 30  'seconds
    retryDuration = 900 'seconds (aka 15 minutes)
    regCode = ""

    'handle validation of response fields 
    for each e in xml.GetBody()
        if e.GetName() = "regCode" then
            regCode = e.GetBody()  'enter this code at website
        elseif e.GetName() = "retryInterval" then
            retryInterval = strtoi(e.GetBody())
        elseif e.GetName() = "retryDuration" then
            retryDuration = strtoi(e.GetBody())
        endif
    next
    
    if regCode = "" then
        Dbg("Parse yields empty registration code")
        ShowConnectionFailed()
    endif
    
    m.retryDuration = retryDuration
    m.retryInterval = retryInterval
    m.regCode = regCode
    
    return regCode
End Function

Function displayRegistrationScreen() As Object
    flickr = LoadFlickr()
    
    regsite   = "go to " + flickr.link_prefix + "/flickr"
    regscreen = CreateObject("roCodeRegistrationScreen")
    regscreen.SetMessagePort(CreateObject("roMessagePort"))
    
    regscreen.SetTitle("")
    regscreen.AddParagraph("Please link your Roku player to your Flickr account")
    regscreen.AddFocalText(" ", "spacing-dense")
    regscreen.AddFocalText("From your computer,", "spacing-dense")
    regscreen.AddFocalText(regsite, "spacing-dense")
    regscreen.AddFocalText("and enter this code to activate:", "spacing-dense")
    regscreen.SetRegistrationCode("retrieving code...")
    regscreen.AddParagraph("This screen will automatically update as soon as your activation completes")
    regscreen.AddButton(0, "Get a new code")
    regscreen.AddButton(1, "Back")
    regscreen.Show()
    
    return regscreen
End Function

'******************************************************************
'** Check the status of the registration to see if we've linked
'** Returns:
'**     0 - We're registered. Proceed.
'**     1 - Reserved. Used by calling function.
'**     2 - We're not registered. There was an error, abort.
'**     3 - We're not registered. Keep trying.
'******************************************************************
Function checkRegistrationStatus(sn As String, regCode As String) As Integer
    oa = Oauth()
    flickr = LoadFlickr()
    
    print "checking registration status"
    http = NewHttp(flickr.link_prefix+"/getRegResult?service=flickr&partner=roku&deviceID="+sn+"&regCode="+regCode)
    
    while true
        rsp = http.getToStringWithTimeout(30)
        print rsp
        xml=ParseXML(rsp)
        if xml=invalid then
            print "Can't parse check registration status response"
            ShowConnectionFailed()
            return 2
        endif
        
        if xml.GetName() <> "result" then
            print "unexpected check registration status response: ", xml.GetName()
            ShowConnectionFailed()
            return 2
        endif
        
        if islist(xml.GetBody()) = true then
            for each e in xml.GetBody()
                if e.GetName() = "status" then
                    status = e.GetBody()
                    
                    if status="failure" then
                        ShowConnectionFailed()
                        return 2
                    else if status="incomplete" then
                        return 3
                    endif
                else if e.GetName() = "oauth_verifier" then
                    oa.verifier = e.GetBody()
                    return 0
                endif
            next
        endif
    end while
End Function

'******************************************************
'Show congratulations screen
'******************************************************
Sub showCongratulationsScreen()
    port = CreateObject("roMessagePort")
    screen = CreateObject("roParagraphScreen")
    screen.SetMessagePort(port)
    
    screen.AddHeaderText("Congratulations!")
    screen.AddParagraph("You have successfully linked your Roku player to your Flickr account")
    screen.AddParagraph("Select 'start' to begin.")
    screen.AddButton(1, "start")
    screen.Show()
    
    while true
        msg = wait(0, screen.GetMessagePort())
        
        if type(msg) = "roParagraphScreenEvent"
            if msg.isScreenClosed()
                print "Screen closed"
                exit while                
            else if msg.isButtonPressed()
                print "Button pressed: "; msg.GetIndex(); " " msg.GetData()
                exit while
            else
                print "Unknown event: "; msg.GetType(); " msg: "; msg.GetMessage()
                exit while
            endif
        endif
    end while
End Sub