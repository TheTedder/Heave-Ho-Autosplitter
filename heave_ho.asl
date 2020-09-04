state("HeaveHo") {}

startup
{
    vars.PAGE_EXECUTE_ANY = MemPageProtect.PAGE_EXECUTE | MemPageProtect.PAGE_EXECUTE_READ | MemPageProtect.PAGE_EXECUTE_READWRITE | MemPageProtect.PAGE_EXECUTE_WRITECOPY;

    vars.JustStarted = false;
    vars.offset = 0.0;
    vars.TotalRunTime = 0.0f;
    vars.CurrentRunTime = 0.0f;

    vars.OnStart = (EventHandler) (
        (object sender, EventArgs e) => {
            vars.JustStarted = true;
            vars.offset = 0.0;
            vars.TotalRunTime = 0.0;
        }
    );

    timer.OnStart += vars.OnStart;
}

shutdown
{
    timer.OnStart -= vars.OnStart;
}

init
{
    // Version checking using hash
    vars.gamePath = modules.First().FileName + "\\..\\HeaveHo_Data\\Managed\\Assembly-CSharp.dll";
    print("[ASL] Reading bytes");
    byte[] dllBytes = File.ReadAllBytes(vars.gamePath);
    print("[ASL] Hashing bytes");
    System.Security.Cryptography.SHA256 hasher = System.Security.Cryptography.SHA256.Create();
    byte[] hashed = hasher.ComputeHash(dllBytes);
    string s = "";
    foreach (byte b in hashed) s += b;
    if (s == "2336514740711751125296795513677151228992114533192051056830181341724411522967") version = "1.0";
    else if (s == "36112821086181635956130462322119323419631435315621402321061141758778815141202") version = "1.1";
    else version = "NA";
    print("[ASL] Hash: " + s);
    print("[ASL] Version: " + version);

    // Version specific setup
    var GMAwakeSigTarget = new SigScanTarget();
    int gmOffset = 0x00;
    if (version == "1.0") {
      GMAwakeSigTarget = new SigScanTarget(0,
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
      gmOffset = 0x14;
    } else if (version == "1.1" || version == "NA") {
      GMAwakeSigTarget = new SigScanTarget(0,
        "55",
        "48 8B EC",
        "48 81 EC ?? ?? ?? ??",
        "48 89 75 F8",
        "48 8B F1",
        "48 C7 45 C8 ?? ?? ?? ??",
        "48 C7 45 D0 ?? ?? ?? ??",
        "48 C7 45 D8 ?? ?? ?? ??",
        "48 B8 ?? ?? ?? ?? ?? ?? ?? ??",
        "48 8B 08"
      );
      gmOffset = 0x2c;
    }

    // Crashes if incorrect signature provided
    var pages = game.MemoryPages();
    SignatureScanner scanner = new SignatureScanner(game, modules.First().BaseAddress, modules.First().ModuleMemorySize);
    IntPtr address = IntPtr.Zero;
    bool found = false;
    uint count = 0;
    foreach (MemoryBasicInformation page in pages)
    {
        if ((uint)(page.Protect & vars.PAGE_EXECUTE_ANY) > 0)
        {
            print("[ASL] scanning page " + count.ToString());
            scanner.Address = page.BaseAddress;
            scanner.Size = (int)page.RegionSize.ToUInt32();
            address = scanner.Scan(GMAwakeSigTarget, 16);
            if (address != IntPtr.Zero) {
              found = true;
              break;
            }
        }
        count++;
    }

    if (!found)
    {
      print("[ASL] Could not find GameManager::Awake");
      return;
    }

    print("[ASL] GameManager::Awake found at: 0x" + address.ToString("X16"));

    // Get game manager instance
    IntPtr mGameManager = new IntPtr(memory.ReadValue<long>(address + gmOffset));
    vars.GameManager = memory.ReadPointer(mGameManager);
    print("[ASL] GameManager::Instance found at: 0x" + vars.GameManager.ToString("X16"));
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

    // Get necessary variables with offsets from game manager
    IntPtr metricsManager = memory.ReadPointer(((IntPtr)vars.GameManager)+0xB8);
    IntPtr currentWorldMetrics = memory.ReadPointer(metricsManager+0x10);
    IntPtr levelTimesArray = memory.ReadPointer(currentWorldMetrics+0x10);
    current.levelTimesLength = memory.ReadValue<int>(levelTimesArray+0x18);
    vars.levelTimes = memory.ReadPointer(levelTimesArray+0x10);
}

gameTime
{
    if (current.levelTimesLength < old.levelTimesLength)
      vars.TotalRunTime += vars.CurrentRunTime;

    vars.CurrentRunTime = 0.0f;
    for (int i = 0; i < current.levelTimesLength; i++)
      vars.CurrentRunTime += memory.ReadValue<float>( ((IntPtr)vars.levelTimes) + 0x20 + (4 * i));

    if (vars.JustStarted)
    {
        vars.JustStarted = false;
        vars.offset = vars.CurrentRunTime;
    }

    return TimeSpan.FromSeconds((double)(vars.TotalRunTime + vars.CurrentRunTime) - vars.offset);
}

exit
{
    current.levelTimesLength = 0;
}

split
{
    return current.levelTimesLength > old.levelTimesLength;
}

isLoading
{
    return true;
}
