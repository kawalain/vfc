function Get-UiText {
    param([string]$Key,[string]$Language='en-US',[object[]]$Values=@())
    $english=@{
        Browse='Browse';Scan='Scan';Symbols='Show symbols';Reset='Reset selected';Ready='Ready';Cancel='Cancel';Apply='Apply'
        OpenAppData='Open application data folder';RemoveOverride='Remove override';TaskRemoveOverride='Remove override';RemoveConfirm='Remove the generated override folder? A Zstandard backup will be kept.';Removed='Override removed. Restart the game.'
        ApplySuccess="Successfully processed {0} files.`nFonts will be applied on the next launch.";OperationError="An error occurred.`nPlease refer to the log file.";LogFile='log file'
        CopyValues='Copy values';PasteValues='Paste values';ContextFont='Replacement font';ContextScale='Size factor (0.1–4.0x)';ContextSize='Font size (VGUI pixels)';Save='Save settings';Saved='Settings saved'
        Original='Original font';Replacement='Replacement font';Scale='Size factor (0.1x - 4.0x)';Uses='Uses';Language='Language'
        Hint='Select rows, then choose a font above. Double-click Replacement or Uses for details.'
        Applied='Applied and verified: {0} fonts; {1} sizes. Restart the game.';Cancelled='Cancelled.';Cancelling='Cancelling...';Closing='Finishing current operation before closing...'
        OriginalSizes='Original sizes: {0} px; each original size is multiplied by this factor.'
        GameFont='Game/HUD font file: {0}';InstalledFont='Installed Windows font: {0}';Unavailable='Preview unavailable';MissingFont='No matching font could be resolved for preview. This is not a game-rendering test.'
        UsesTitle='Font definitions: {0}';Files='Files / definitions';Source='Source: {0} | line {1} | {2} / {3}';NoSource='Source text is unavailable.';Copy='Copy';SelectAll='Select all'
        Starting='Starting...';Locating='Locating game folder';Discovering='Locating Source games';SearchPaths='Reading game search paths';SchemeDiscovery='Discovering Scheme files';Indexing='Indexing {0}';Scanning='Scanning {0}';Previews='Loading Windows font previews';Locations='Loading source locations';Saving='Saving verified schemes';Verifying='Verifying {0}'
        Resolving='Resolving {0}';Reading='Reading {0}';LocaleError='Could not save language preference: {0}';SavingSettings='Saving settings';PreparingSave='Preparing settings';LoadingSettings='Loading settings';ExportingSettings='Exporting settings'
        FileMenu='&File';EditMenu='&Edit';ViewMenu='&View';ChooseGame='Choose game folder...';Import='Import settings...';Export='Export settings...';Exit='Exit';Undo='Undo';Redo='Redo'
        Find='Find...';FindNext='Next';FindPrevious='Previous';FindHint='Font, key or file name';FindCount='{0} / {1}';FindEmpty='No matches'
        About='About';AboutDescription='VGUI2 font replacement script';CloseDialog='Close';TaskScan='Scan';TaskSave='Save';TaskBuild='Apply';TaskImport='Import settings';TaskExport='Export settings'
        ExpandAll='Expand all';CollapseAll='Collapse all';Node='Font group / alias / variant';GameFolder='Game folder'
        Theme='Theme';ThemeSystem='Follow Windows';ThemeLight='Light';ThemeDark='Dark';ThemeAMOLED='AMOLED (black)'
        ResetConfirm='Reset explicit settings to their inherited defaults? Child overrides are kept. Root defaults are the original font and 1.0x.'
        DiscardConfirm='There are unapplied changes. Discard them and continue?'
        Imported='Settings imported. Apply to write the game files.';Exported='Settings exported.'
        TreeHint='Expand a font group to edit aliases and variants. Double-click an alias or original font to view its source.'
        InheritanceHint='● = explicit override. Parent changes propagate only to inherited fields. Double-click an explicit value, or Delete a selected row, to reset.'
    }
    $korean=@{
        Browse='찾아보기';Scan='스캔';Symbols='심볼 글꼴 표시';Reset='선택 항목 초기화';Ready='준비';Cancel='중단';Apply='적용'
        OpenAppData='프로그램 데이터 폴더 열기';RemoveOverride='적용 해제';TaskRemoveOverride='적용 해제';RemoveConfirm='생성된 적용 폴더를 제거할까요? zstd 백업은 보관됩니다.';Removed='적용을 해제했습니다. 게임을 다시 실행해주세요.'
        ApplySuccess="성공적으로 {0}개의 파일을 처리했습니다.`n다음 실행부터 글꼴이 적용됩니다.";OperationError="오류가 발생했습니다.`n로그 파일을 참고해주세요.";LogFile='로그 파일'
        CopyValues='값 복사';PasteValues='값 붙여넣기';ContextFont='대체 글꼴';ContextScale='크기 배율 (0.1–4.0배)';ContextSize='글자 크기 (VGUI 픽셀)';Save='설정 저장';Saved='설정을 저장했습니다'
        Original='원본 글꼴';Replacement='대체 글꼴';Scale='크기 배율 (0.1x - 4.0x)';Uses='사용 위치';Language='언어'
        Hint='항목 선택 후 위에서 글꼴을 선택하세요. 대체 글꼴·사용 위치를 두 번 누르면 상세 편집·보기가 열립니다.'
        Applied='파일 검증 완료: 글꼴 {0}개, 크기 {1}개 변경. 게임을 다시 실행하세요.';Cancelled='중단되었습니다.';Cancelling='중단 중...';Closing='현재 작업을 마친 후 종료합니다...'
        OriginalSizes='원본 크기: {0} px; 각 원본 크기에 배율을 곱합니다.'
        GameFont='게임/HUD 글꼴 파일: {0}';InstalledFont='Windows 설치 글꼴: {0}';Unavailable='미리보기 불가';MissingFont='미리보기용 글꼴을 찾지 못했습니다. 게임 렌더링 실패를 의미하지는 않습니다.'
        UsesTitle='글꼴 정의 위치: {0}';Files='파일 / 정의';Source='원본: {0} | {1}행 | {2} / {3}';NoSource='원본 내용을 읽을 수 없습니다.';Copy='복사';SelectAll='모두 선택'
        Starting='시작 중...';Locating='게임 경로 확인 중';Discovering='지원 게임 경로 검색 중';SearchPaths='게임 파일 검색 경로 읽는 중';SchemeDiscovery='Scheme 파일 찾는 중';Indexing='{0} 목록 읽는 중';Scanning='{0} 검색 중';Previews='Windows 글꼴 미리보기 로딩 중';Locations='원본 위치 로딩 중';Saving='검증된 파일 저장 중';Verifying='{0} 검증 중'
        Resolving='{0} 의존성 해석 중';Reading='{0} 읽는 중';LocaleError='언어 설정을 저장하지 못했습니다: {0}';SavingSettings='설정 저장 중';PreparingSave='설정 준비 중';LoadingSettings='설정 불러오는 중';ExportingSettings='설정 내보내는 중'
        FileMenu='파일(&F)';EditMenu='편집(&E)';ViewMenu='보기(&V)';ChooseGame='게임 폴더 지정...';Import='설정 불러오기...';Export='설정 내보내기...';Exit='종료';Undo='실행 취소';Redo='다시 실행'
        Find='검색...';FindNext='다음';FindPrevious='이전';FindHint='글꼴, 키 또는 파일 이름';FindCount='{0} / {1}';FindEmpty='검색 결과 없음'
        About='About';AboutDescription='VGUI2 글꼴 대체 스크립트';CloseDialog='닫기';TaskScan='스캔';TaskSave='저장';TaskBuild='적용';TaskImport='설정 불러오기';TaskExport='설정 내보내기'
        ExpandAll='모두 펼치기';CollapseAll='모두 접기';Node='글꼴 집합 / alias / variant';GameFolder='게임 폴더'
        Theme='테마';ThemeSystem='Windows 설정 따르기';ThemeLight='라이트';ThemeDark='다크';ThemeAMOLED='AMOLED (검정)'
        ResetConfirm='개별 설정을 부모에게 상속받는 기본값으로 되돌릴까요? 하위의 개별 설정은 유지됩니다. 최상위 기본값은 원본 글꼴과 1.0배입니다.'
        DiscardConfirm='아직 적용하지 않은 변경이 있습니다. 변경을 버리고 계속할까요?'
        Imported='설정을 불러왔습니다. 적용하면 게임 파일에 저장됩니다.';Exported='설정을 내보냈습니다.'
        TreeHint='글꼴 집합을 펼쳐 alias·variant를 설정하세요. alias나 원본 글꼴을 두 번 누르면 원본 코드를 봅니다.'
        InheritanceHint='● = 개별 설정. 상위 변경은 상속 중인 값에만 전파됩니다. 개별 값을 두 번 누르거나 선택 후 Delete를 누르면 초기화합니다.'
    }
    $table=$english; if($Language -eq 'ko-KR'){$table=$korean}
    if(-not $table.ContainsKey($Key)){return $Key}
    if($Values.Count -gt 0){return [string]::Format([Globalization.CultureInfo]::CurrentCulture,$table[$Key],$Values)}
    return $table[$Key]
}
function Get-WindowsGuiLocale {
    # Read the user's Windows display-language setting independently of the
    # host/runspace culture. An explicit override can also await the next login.
    $culture=$null
    try{$culture=Get-WinUILanguageOverride -ErrorAction Stop}catch{}
    if(-not $culture){
        try{
            if(-not ('VguiLanguageNative' -as [type])){
                Add-Type -TypeDefinition @"
using System.Runtime.InteropServices;
public static class VguiLanguageNative {
    [DllImport("kernel32.dll")]
    public static extern ushort GetUserDefaultUILanguage();
}
"@
            }
            $culture=[Globalization.CultureInfo]::GetCultureInfo([int][VguiLanguageNative]::GetUserDefaultUILanguage())
        }catch{$culture=[Globalization.CultureInfo]::CurrentUICulture}
    }
    if($culture.TwoLetterISOLanguageName -eq 'ko'){return 'ko-KR'}
    return 'en-US'
}

function Get-GuiLocale {
    param([string]$Requested)
    if($Requested){return $Requested}
    return (Read-LayoutPreferences).Locale
}
function ConvertTo-UiStatus {
    param([string]$Message,[string]$Language)
    $keys=@{'Starting...'='Starting';'Locating game folder'='Locating';'Locating Source games'='Discovering';'Loading Windows font previews'='Previews';'Loading source locations'='Locations';'Saving verified schemes'='Saving';'Preparing settings'='PreparingSave';'Saving settings'='SavingSettings';'Loading settings'='LoadingSettings';'Exporting settings'='ExportingSettings'}
    if($keys.ContainsKey($Message)){return Get-UiText $keys[$Message] $Language}
    if($Message -eq 'Reading game search paths'){return Get-UiText 'SearchPaths' $Language}
    if($Message -eq 'Discovering Scheme files'){return Get-UiText 'SchemeDiscovery' $Language}
    foreach($prefix in @('Verifying','Resolving','Reading','Indexing','Scanning')){if($Message.StartsWith($prefix+' ')){return Get-UiText $prefix $Language @($Message.Substring($prefix.Length+1))}}
    return $Message
}
