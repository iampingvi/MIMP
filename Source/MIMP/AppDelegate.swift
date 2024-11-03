import Cocoa

class AppDelegate: NSObject, NSApplicationDelegate {

    func applicationDidFinishLaunching(_ aNotification: Notification) {
        // Проверяем, не запущено ли уже приложение
        if let existingApp = NSWorkspace.shared.runningApplications.first(where: { $0 != NSRunningApplication.current && $0.bundleIdentifier == Bundle.main.bundleIdentifier }) {
            // Если приложение уже запущено, активируем существующее окно
            existingApp.activate(options: [])
            // Закрываем текущую копию приложения
            NSApplication.shared.terminate(nil)
            return
        }
    }

    @MainActor
    func application(_ application: NSApplication, open urls: [URL]) {
        guard let url = urls.first,
              AudioFormat.allExtensions.contains(url.pathExtension.lowercased()) else {
            return
        }

        // Activate the existing window
        if let window = NSApp.windows.first {
            window.makeKeyAndOrderFront(nil)
        }

        Task {
            try? await AudioPlayer.shared.load(url: url)
        }
    }

    // MARK: - Core Data stack

    lazy var persistentContainer: NSPersistentContainer = {
        /*
         The persistent container for the application. This implementation
         creates and returns a container, having loaded the store for the
         application to it. This property is optional since there are legitimate
         error conditions that could cause the creation of the store to fail.
        */
        let container = NSPersistentContainer(name: "MIMP")
        container.loadPersistentStores(completionHandler: { (storeDescription, error) in
            if let error = error as NSError? {
                // Replace this implementation with code to handle the error appropriately.
                // fatalError() causes the application to generate a crash log and terminate. You should not use this function in a shipping application, although it may be useful during development.

                /*
                 Typical reasons for an error here include:
                 * The parent directory does not exist, cannot be created, or disallows writing.
                 * The persistent store is not accessible, due to permissions or data protection when the device is locked.
                 * The device is out of space.
                 * The store could not be migrated to the current model version.
                 Check the error message to determine what the actual problem was.
                 */
                fatalError("Unresolved error \(error), \(error.userInfo)")
            }
        })
        return container
    }()

    // MARK: - Core Data Saving support

    func saveContext () {
        let context = persistentContainer.viewContext
        if context.hasChanges {
            do {
                try context.save()
            } catch {
                // Replace this implementation with code to handle the error appropriately.
                // fatalError() causes the application to generate a crash log and terminate. You should not use this function in a shipping application, although it may be useful during development.
                let nserror = error as NSError
                fatalError("Unresolved error \(nserror), \(nserror.userInfo)")
            }
        }
    }

} 