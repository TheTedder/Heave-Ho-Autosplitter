state("HeaveHo") {}

startup
{
	vars.Log = (Action<object>)((output) => print("[Heave Ho ASL] " + output));

	vars.JustStarted = false;
	vars.Offset = 0f;
	vars.TotalRunTime = 0f;
	vars.CurrentRunTime = 0f;

	vars.OnStart = (EventHandler)((s, e) =>
	{
		vars.JustStarted = true;
		vars.Offset = 0f;
		vars.TotalRunTime = 0f;
	});

	timer.OnStart += vars.OnStart;
} // startup

init
{
	var classes = new Dictionary<string, uint>
	{
		{ "GameManager", 0x200001D }
	};

	vars.CancelSource = new CancellationTokenSource();
	vars.MonoThread = new Thread(() =>
	{
		vars.Log("Starting thread.");

		var class_count = 0;
		var class_cache = IntPtr.Zero;

		var cancelToken = vars.CancelSource.Token;
		while (!cancelToken.IsCancellationRequested)
		{
			if (game.ModulesWow64Safe().FirstOrDefault(m => m.ModuleName == "mono-2.0-bdwgc.dll") != null)
				break;

			vars.Log("Mono module not loaded.");
			Thread.Sleep(1000);
		}

		while (!cancelToken.IsCancellationRequested)
		{
			var table_size = new DeepPointer("mono-2.0-bdwgc.dll", 0x494118, 0x18).Deref<int>(game);
			var slot = new DeepPointer("mono-2.0-bdwgc.dll", 0x494118, 0x10, 0x8 * (int)(4197980909 % table_size)).Deref<IntPtr>(game);
			for (; slot != IntPtr.Zero; slot = game.ReadPointer(slot + 0x10))
			{
				string slot_key = new DeepPointer(slot + 0x0, 0x0).DerefString(game, 32);
				if (slot_key != "Assembly-CSharp") continue;

				class_count = new DeepPointer(slot + 0x8, 0x4D8).Deref<int>(game);
				class_cache = new DeepPointer(slot + 0x8, 0x4E0).Deref<IntPtr>(game);
			}

			if (class_count > 0 && class_cache != IntPtr.Zero)
				break;

			vars.Log("Assembly-CSharp not found.");
			Thread.Sleep(1000);
		}

		while (!cancelToken.IsCancellationRequested)
		{
			var mono = new Dictionary<string, IntPtr>();
			var allFound = false;

			foreach (var token in classes)
			{
				var klass = game.ReadPointer(class_cache + 0x8 * (int)(token.Value % class_count));
				for (; klass != IntPtr.Zero; klass = game.ReadPointer(klass + 0x108))
				{
					if (game.ReadValue<uint>(klass + 0x58) != token.Value) continue;

					var vtable_size = game.ReadValue<int>(klass + 0x5C);
					mono.Add(token.Key, new DeepPointer(klass + 0xD0, 0x8, 0x40 + 0x8 * vtable_size).Deref<IntPtr>(game));

					vars.Log("Found " + token.Key + " at 0x" + mono[token.Key].ToString("X") + ".");
				}
			}

			if (mono.Count == classes.Count && mono.Values.All(ptr => ptr != IntPtr.Zero))
			{
				vars.Data = new MemoryWatcherList
				{
					new MemoryWatcher<IntPtr>(new DeepPointer(mono["GameManager"] + 0x0, 0xB8, 0x10, 0x10)) { Name = "LevelTimesPtr" }
				};

				vars.Log("Everything found successfully.");
				break;
			}

			vars.Log("Not all classes found.");
			Thread.Sleep(5000);
		}

		vars.Log("Exiting thread.");
	});

	current.LevelTimesCount = 0;

	vars.MonoThread.Start();
} // init

update
{
	if (vars.MonoThread.IsAlive) return false;

	vars.Data.UpdateAll(game);
	current.LevelTimesCount = game.ReadValue<int>((IntPtr)vars.Data["LevelTimesPtr"].Current + 0x18);
	vars.TimesList = game.ReadPointer((IntPtr)vars.Data["LevelTimesPtr"].Current + 0x10);
}

split
{
	return old.LevelTimesCount < current.LevelTimesCount;
}

gameTime
{
	if (old.LevelTimesCount > current.LevelTimesCount)
		vars.TotalRunTime += vars.CurrentRunTime;

	vars.CurrentRunTime = 0f;
	for (int i = 0; i < current.LevelTimesCount; ++i)
		vars.CurrentRunTime += game.ReadValue<float>((IntPtr)vars.TimesList + 0x20 + 0x4 * i);

	if (vars.JustStarted)
	{
		vars.JustStarted = false;
		vars.Offset = vars.CurrentRunTime;
	}

	return TimeSpan.FromSeconds(vars.TotalRunTime + vars.CurrentRunTime - vars.Offset);
}

isLoading
{
	return true;
}

exit
{
	current.LevelTimesCount = 0;
	vars.CancelSource.Cancel();
}

shutdown
{
	timer.OnStart -= vars.OnStart;
	vars.CancelSource.Cancel();
}
