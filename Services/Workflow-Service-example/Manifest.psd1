@{
    Name = 'Workflow-Service'
    Version = '1.0.0'
    EntryPoint = 'Main.ps1'

    RequiredModules = @(
        'Logging'
        'FileSystem'
        'Configuration'
    )

    RequiredPowerShellVersion = '>=5.1'
}