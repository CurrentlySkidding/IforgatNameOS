--[[ aurora.svc.printer ------------------------------------------------------
     Print spooler for CC printers.  Documents are queued, paginated to the
     printer's page size, and written page by page.  Writer, Sheets, Slides
     and the Text Editor all print through here.
----------------------------------------------------------------------------]]

local util    = arequire("lib.util")
local log     = arequire("kernel.log")
local devices = arequire("kernel.devices")

local printer = {}

printer.queue = {}       -- pending jobs
printer.history = {}     -- finished jobs
printer.listeners = {}
printer.nextId = 1

function printer.onChange(fn)
  printer.listeners[#printer.listeners + 1] = fn
end

local function notify(event, job)
  for _, fn in ipairs(printer.listeners) do pcall(fn, event, job) end
end

function printer.available()
  return devices.byClass("printer")
end

function printer.default()
  local list = printer.available()
  return list[1]
end

function printer.status(record)
  if not record or not record.handle then return "offline" end
  local ok, ink = pcall(record.handle.getInkLevel)
  if not ok then return "offline" end
  local paperOk, paper = pcall(record.handle.getPaperLevel)
  if (ink or 0) <= 0 then return "out of ink" end
  if not paperOk or (paper or 0) <= 0 then return "out of paper" end
  return "ready"
end

--- Break a document into printable pages.
--- @param lines table  array of text lines
--- @param pageW number
--- @param pageH number
function printer.paginate(lines, pageW, pageH, title)
  local pages = {}
  local current = {}
  for _, raw in ipairs(lines) do
    local wrapped = util.wrap(raw, pageW)
    if #wrapped == 0 then wrapped = { "" } end
    for _, line in ipairs(wrapped) do
      current[#current + 1] = line
      if #current >= pageH then
        pages[#pages + 1] = current
        current = {}
      end
    end
  end
  if #current > 0 then pages[#pages + 1] = current end
  if #pages == 0 then pages = { { "" } } end
  return pages
end

--- Queue a document.  `content` is a string or an array of lines.
function printer.submit(opts)
  local lines
  if type(opts.content) == "table" then
    lines = opts.content
  else
    lines = util.splitAll(tostring(opts.content or ""), "\n")
  end
  local job = {
    id = printer.nextId,
    title = opts.title or "Untitled",
    lines = lines,
    target = opts.target,          -- peripheral name, or nil for default
    copies = opts.copies or 1,
    state = "queued",
    submitted = os.clock(),
    source = opts.source,
  }
  printer.nextId = printer.nextId + 1
  printer.queue[#printer.queue + 1] = job
  notify("queued", job)
  log.info("printer", ("queued job %d (%s)"):format(job.id, job.title))
  return job
end

--- Print one job synchronously.  Returns pagesPrinted, error.
function printer.run(job)
  local record
  if job.target then
    record = devices.get(job.target)
  else
    record = printer.default()
  end
  if not record or not record.handle then
    job.state = "failed"
    job.error = "no printer attached"
    notify("failed", job)
    return 0, job.error
  end

  local device = record.handle
  local ok, pageW, pageH = pcall(device.getPageSize)
  if not ok then
    job.state = "failed"
    job.error = "printer unavailable"
    notify("failed", job)
    return 0, job.error
  end

  local pages = printer.paginate(job.lines, pageW, pageH, job.title)
  job.pages = #pages
  job.state = "printing"
  notify("printing", job)

  local printed = 0
  for copy = 1, job.copies do
    for index, page in ipairs(pages) do
      local newPage, err = device.newPage()
      if not newPage then
        job.state = "failed"
        job.error = printer.status(record)
        notify("failed", job)
        return printed, job.error
      end
      local label = job.title
      if #pages > 1 then label = ("%s (%d/%d)"):format(job.title, index, #pages) end
      pcall(device.setPageTitle, label:sub(1, 32))
      for row, line in ipairs(page) do
        device.setCursorPos(1, row)
        device.write(line)
      end
      if not device.endPage() then
        job.state = "failed"
        job.error = "could not output the page"
        notify("failed", job)
        return printed, job.error
      end
      printed = printed + 1
      job.progress = printed / (#pages * job.copies)
      notify("progress", job)
    end
  end

  job.state = "done"
  job.printed = printed
  notify("done", job)
  log.info("printer", ("job %d printed %d pages"):format(job.id, printed))
  return printed
end

--- Drain the queue.  Called by the spooler service process.
function printer.pump()
  local job = table.remove(printer.queue, 1)
  if not job then return false end
  printer.run(job)
  table.insert(printer.history, 1, job)
  while #printer.history > 20 do table.remove(printer.history) end
  return true
end

--- The spooler service body, run as an Aurora process.
function printer.service()
  while true do
    if #printer.queue > 0 then
      local ok, err = pcall(printer.pump)
      if not ok then log.error("printer", tostring(err)) end
    end
    os.sleep(0.4)
  end
end

--- Print a file straight from disk.
function printer.printFile(path, target)
  local data = util.readFile(path)
  if not data then return nil, "cannot read " .. path end
  return printer.submit({
    title = fs.getName(path),
    content = data,
    target = target,
    source = path,
  })
end

return printer
