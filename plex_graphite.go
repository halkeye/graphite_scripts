package main

import (
	"flag"
	"fmt"
	"github.com/jrudio/go-plex-client"
	"github.com/kardianos/osext"
	"github.com/marpaia/graphite-golang"
	"gopkg.in/ini.v1"
	"log"
	"strconv"
)

type config struct {
	interval int
	config   string
	debug    bool
	dryRun   bool
}

func getPlexData(config config, iniCfg *ini.Section) map[string]int {
	users := make(map[string]int)

	Plex, err := plex.New("https://"+iniCfg.Key("host").String()+":"+iniCfg.Key("port").String(), iniCfg.Key("token").String())
	if err != nil {
		log.Fatal(err)
	}

	currentSession, err := Plex.GetSessions()
	if err != nil {
		log.Fatal(err)
	}
	for idx := range currentSession.Video {
		users[currentSession.Video[idx].User.Title]++
	}
	for idx := range currentSession.Track {
		users[currentSession.Track[idx].User.Title]++
	}
	return users
}

func newGraphite(config config, iniCfg *ini.Section) *graphite.Graphite {
	port, err := strconv.Atoi(iniCfg.Key("port").String())
	if err != nil {
		log.Fatal(err)
	}
	host := iniCfg.Key("host").String()
	if config.dryRun {
		return graphite.NewGraphiteNop(host, port)
	}

	// try to connect a graphite server
	Graphite, err := graphite.NewGraphite(host, port)
	// if you couldn't connect to graphite, use a nop
	if err != nil {
		Graphite = graphite.NewGraphiteNop(host, port)
	}
	return Graphite
}

func main() {
	folderPath, err := osext.ExecutableFolder()
	if err != nil {
		log.Fatal(err)
	}

	config := config{}
	flag.IntVar(&config.interval, "interval", 10, "sleep time")
	flag.StringVar(&config.config, "config", folderPath+"/config.ini", "Filename of the config file")
	flag.BoolVar(&config.debug, "debug", false, "Debug")
	flag.BoolVar(&config.dryRun, "dry-run", true, "Don't actually submit to graphite")
	flag.Parse()

	cfg, err := ini.Load(config.config)
	if err != nil {
		log.Fatal(err)
	}

	plexCfg, err := cfg.GetSection("plex")
	if err != nil {
		log.Fatal(err)
	}
	graphiteCfg, err := cfg.GetSection("graphite")
	if err != nil {
		log.Fatal(err)
	}

	Graphite := newGraphite(config, graphiteCfg)
	plexData := getPlexData(config, plexCfg)

	for username, val := range plexData {
		key := "plex.user_activity." + username
		Graphite.SimpleSend(key, strconv.Itoa(val))

		if config.debug {
			fmt.Printf("%s %d\n", key, val)
		}
	}
}
