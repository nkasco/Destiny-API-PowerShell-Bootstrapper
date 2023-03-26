#################################################################
# Destiny API Bootstrapper                                      #
# Written By: Nathan Kasco                                      #
# Date: 3/26/2023                                               #
#################################################################

param(
    [switch]
    $UseConfig #If desired, place JSON 1 level up from this folder in DestinyAPIConfig.json
)

$ScriptPath = Split-Path $MyInvocation.MyCommand.Path

#Configuration - Set variables here
if(!($UseConfig)){
    $env:BUNGIE_API_KEY = ""
    $clientId = ""
    $client_secret = ""
    $redirectUri = "https://localhost.local" #Override if desired, otherwise this must match what you configured for your app
} else {
    $ConfigPath = "$ScriptPath\..\DestinyAPIConfig.json"
    $ConfigContent = Get-Content -Raw $ConfigPath
    $ConfigJSON = ConvertFrom-Json $ConfigContent
    $env:BUNGIE_API_KEY = $ConfigJSON.APIKey
    $clientId = $ConfigJSON.ClientID
    $client_secret = $ConfigJSON.ClientSecret
    $redirectUri = $ConfigJSON.RedirectURI
}

#TODO: Add logic to use a refresh token if one exists

#Initialization
try{
    Write-Progress -Activity "Initializing..."
    Add-Type -AssemblyName System.Windows.Forms -ErrorAction Stop
    [void][reflection.assembly]::LoadFile("$ScriptPath\source\Microsoft.Web.WebView2.WinForms.dll")
    [void][reflection.assembly]::LoadFile("$ScriptPath\source\Microsoft.Web.WebView2.Core.dll")

    $authUrl = "https://www.bungie.net/en/OAuth/Authorize"
    $tokenUrl = "https://www.bungie.net/platform/app/oauth/token/"

    $authorizationUrl = "$($authUrl)?response_type=code&client_id=$clientId&state=1234&redirect_uri=$redirectUri"

    # Create a new form object
    $form = New-Object System.Windows.Forms.Form -ErrorAction Stop
    $form.Text = "Bungie.net Authorization"
    $form.Width = 800
    $form.Height = 600

    [Microsoft.Web.WebView2.WinForms.WebView2]$webview = New-Object 'Microsoft.Web.WebView2.WinForms.WebView2'
    $webview.CreationProperties = New-Object 'Microsoft.Web.WebView2.WinForms.CoreWebView2CreationProperties' -ErrorAction Stop
    $webview.CreationProperties.UserDataFolder = "$ScriptPath\source\UserData"
    $webview.Dock = "Fill"
    $webview.source = $authorizationUrl

    #Since the redirect goes to localhost, close when it gets navigated there since there is nothing for the user to do
    $webview.Add_SourceChanged({
        if($webview.source -match "localhost"){
            $Form.close() | Out-Null
        }
    })

    # Add the WebBrowser control to the form
    $form.Controls.Add($webview)

    $form.Add_Shown({$form.Activate()})
    $form.ShowDialog() | Out-Null

    #Once the user closes the window the script will continue and find the auth code from the url source

    if($webview.source.query -match "code="){
        $authorizationCode = $webview.source.query -replace "&state.*" -replace "\?code="
    } else {
        Read-Host "Authentication failed, press enter to exit"
        Exit 1603
    }

    #Fetch an Access Token
    $tokenRequestParams = @{
        grant_type = "authorization_code"
        code = $authorizationCode
        client_id = $clientId
        client_secret = $client_secret
        redirect_uri = $redirectUri
    }

    Write-Progress -Activity "Fetching auth token..."
    $tokenResponse = Invoke-RestMethod -Method Post -Uri $tokenUrl -Body $tokenRequestParams -ErrorAction Stop

    $accessToken = $tokenResponse.access_token
    $headers = @{ "Authorization" = "Bearer $accessToken"; "X-API-Key" = $env:BUNGIE_API_KEY }

    #IMPORTANT - AT THIS POINT YOU HAVE AN AUTH TOKEN, LISTED BELOW IS A SAMPLE OF HOW IT CAN BE USED

    #Get Bungie User Data
    $getUrl = "https://www.bungie.net/Platform/User/GetMembershipsForCurrentUser/"

    Write-Progress -Activity "Fetching profile data..."
    $userResponse = Invoke-RestMethod -Method Get -Uri $getUrl -Headers $headers -ErrorAction Stop
    $destinyMembershipId = $userResponse.Response.destinyMemberships[0].membershipId
    $membershipType = $userResponse.Response.destinyMemberships[0].membershipType

    $profileData = Invoke-RestMethod -Method Get -Uri "https://www.bungie.net/Platform/Destiny2/$membershipType/Profile/$destinyMembershipId/?components=100" -Headers $headers -ErrorAction Stop

    $profileData.response.profile.data
    Write-Progress -Activity " " -Completed
} catch {
    Write-Error "An error occurred - $_"
}
Read-Host "Press enter to exit"