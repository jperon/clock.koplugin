local loadmoonfile = require("moonscript").loadfile
package.preload["clockwidget"] = package.preload["clockwidget"] or loadmoonfile("plugins/clock.koplugin/clockwidget.moon")
package.preload["clock"] = package.preload["clock"] or loadmoonfile("plugins/clock.koplugin/clock.moon")

return require("clock")
