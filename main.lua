local loadmoonfile = require("moonscript").loadfile
package.preload["clockwidget"] = package.preload["clockwidget"] or loadmoonfile("plugins/analogclock.koplugin/clockwidget.moon")
package.preload["analogclock"] = package.preload["analogclock"] or loadmoonfile("plugins/analogclock.koplugin/analogclock.moon")

return require("analogclock")
