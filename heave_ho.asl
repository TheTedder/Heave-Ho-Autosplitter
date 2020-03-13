state("HeaveHo") {}

startup
{
    //print("[ASL] Loaded vars: " + String.Join(", ", (vars as IDictionary<string,object>).Keys));
    vars.PAGE_EXECUTE_ANY = MemPageProtect.PAGE_EXECUTE | MemPageProtect.PAGE_EXECUTE_READ | MemPageProtect.PAGE_EXECUTE_READWRITE | MemPageProtect.PAGE_EXECUTE_WRITECOPY;
    vars.JustStarted = false;
    vars.offset = 0.0;
    vars.GMAwakeSigTarget = new SigScanTarget(0,
        "55",
        "48 8B EC",
        "48 81 EC ?? ?? ?? ??",
        "48 89 75 ??",
        "48 8B F1",
        "48 B8 ?? ?? ?? ?? ?? ?? ?? ??",
        "48 8B 08",
        "33 D2",
        "48 8D 64 24 ??",
        "49 BB ?? ?? ?? ?? ?? ?? ?? ??"
    );
    
    //TODO: add the full Awake method signature
    vars.CurrentRunTime = 0.0f;
    vars.TotalRunTime = 0.0f;
    //this doesn't work.
    //current.LevelTimesLength = 0;
    EventHandler onStart = 
    (object sender, EventArgs e) => {
        vars.TotalRunTime = 0.0;
        vars.JustStarted = true;
        vars.offset = 0.0;
    };
    vars.OnStart = onStart;
    timer.OnStart += vars.OnStart;
}

shutdown
{
    timer.OnStart -= vars.OnStart;
}

init
{
    var pages = game.MemoryPages();
    SignatureScanner scanner = new SignatureScanner(game, modules.First().BaseAddress, modules.First().ModuleMemorySize);
    IntPtr address = IntPtr.Zero;
    bool found = false;
    print("[ASL] Scanning...");
    //probably better not to use a while loop here but eh
    while (address == IntPtr.Zero)
    {
        uint count = 0;
        foreach (MemoryBasicInformation page in pages)
        {
            if ((uint)(page.Protect & vars.PAGE_EXECUTE_ANY) > 0)
            {
                print("[ASL] scanning page " + count.ToString());
                scanner.Address = page.BaseAddress;
                scanner.Size = (int)page.RegionSize.ToUInt32();
                address = scanner.Scan(vars.GMAwakeSigTarget, 16);
                if (address != IntPtr.Zero)
                {
                    found = true;
                    break;
                }
            }
            count++;
        }
    }
    
    print("[ASL] GameManager::Awake found at: 0x" + address.ToString("X16"));
    
    IntPtr mGameManager = new IntPtr(memory.ReadValue<long>(address + 0x14));
    IntPtr GameManager = memory.ReadPointer(mGameManager);
    print("[ASL] GameManager::Instance found at: 0x" + GameManager.ToString("X16"));
    vars.LevelTimesPtr = new DeepPointer(GameManager+0xB8, 0x10, 0x10);
}

update
{
    //GameManager.levelSelectorInstance: [0x78]
    //IntPtr levelSelectorInstance = memory.ReadPointer((IntPtr)vars.GameManager+0x78);
    //print("[ASL] found LevelSelector at " + levelSelectorInstance.ToString("X16"));
    //LevelSelector.currentLevelIndex: 0x58
    //current.LevelIndex = memory.ReadValue<int>(levelSelectorInstance+0x98);
    //print(String.Format("[ASL] level {0} loaded", current.LevelIndex));
    //IntPtr LevelProperties = memory.ReadPointer(levelSelectorInstance+0x58);
    //IntPtr LevelName = memory.ReadPointer(LevelProperties+0x10);
    //int LevelNameLength = memory.ReadValue<int>(LevelName+0x10);
    //print(String.Format("[ASL] level name is {0} chars long.", LevelNameLength));
    //current.LevelName = memory.ReadString(LevelName+0x14, LevelNameLength * 2);
    //print(String.Format("[ASL] current level: {0}", current.LevelName));
    
    //IntPtr scoreManager = memory.ReadPointer((IntPtr)vars.GameManager+0xA8);
    //IntPtr players = memory.ReadPointer(((IntPtr)vars.GameManager)+0xf0);
    //IntPtr _items = memory.ReadPointer(players+0x10);
    //IntPtr player = memory.ReadPointer(_items+0x20); //don't ask me why this works.
    //IntPtr currentCharacter = memory.ReadPointer(player+0x170);
    //IntPtr levelManager = memory.ReadPointer(currentCharacter+0x100);
    //IntPtr levelRules = memory.ReadPointer(levelManager+0x20);
    //IntPtr victoryTrigger = memory.ReadPointer(levelManager+0x30);
    //current.IsVictory = memory.ReadValue<bool>(victoryTrigger+0x88);
    //print(player.ToString());
    IntPtr levelTimes = new IntPtr(vars.LevelTimesPtr.Deref<long>(game));
    //print(levelTimes.ToString("X16"));
    current.LevelTimesLength = memory.ReadValue<int>(levelTimes+0x18);
    vars.LevelTimes = memory.ReadPointer(levelTimes+0x10);
}

gameTime
{
    if (current.LevelTimesLength < old.LevelTimesLength)
    {
        vars.TotalRunTime += vars.CurrentRunTime;
    }
    
    float runTime = 0.0f;
    for (int i = 0; i < current.LevelTimesLength; i++)
    {
        runTime += memory.ReadValue<float>( ((IntPtr)vars.LevelTimes) + 0x20 + (4 * i));
    }
    vars.CurrentRunTime = runTime;
    if (vars.JustStarted)
    {
        vars.JustStarted = false;
        vars.offset = vars.CurrentRunTime;
    }
    //if(current.IsVictory)
    //{
        return TimeSpan.FromSeconds((double)(vars.TotalRunTime + vars.CurrentRunTime) - vars.offset);
    //}
}

start
{
    //return current.LevelName == "Tuto1" && old.LevelName != "Tuto1";
}

split
{
    return current.LevelTimesLength > old.LevelTimesLength;
}

isLoading
{
    return true;
}