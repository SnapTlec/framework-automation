class Response{
    [bool]$Status
    [PSCustomObject]$Data
    [string[]]$Messages

    Response([bool]$status, [PSCustomObject]$data, [string[]]$messages){
        $this.Status = $status
        $this.Data = $data
        $this.Messages = $messages
    }

}