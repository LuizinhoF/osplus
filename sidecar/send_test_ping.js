const WebSocket = require("ws");

const RELAY_URL = process.argv[2] || "ws://localhost:3000";
const ROOM = process.argv[3] || "TEST";
const DELAY = 10;

console.log(`Will send a DANGER ping to room "${ROOM}" in ${DELAY} seconds...`);
console.log("Switch to the game now!\n");

let countdown = DELAY;
const timer = setInterval(() => {
  countdown--;
  if (countdown > 0) {
    process.stdout.write(`  ${countdown}...\r`);
  }
}, 1000);

setTimeout(() => {
  clearInterval(timer);
  const ws = new WebSocket(RELAY_URL);

  ws.on("open", () => {
    console.log("Connected to relay");
    ws.send(JSON.stringify({ type: "join", room: ROOM }));
  });

  ws.on("message", (raw) => {
    const msg = JSON.parse(raw.toString());
    if (msg.type === "joined") {
      console.log(`Joined room: ${msg.room}`);
      const ping = {
        type: "ping",
        key: "DANGER",
        x: 0,
        y: 0,
        z: 0,
      };
      ws.send(JSON.stringify(ping));
      console.log(`\nSent DANGER ping at (0, 0, 0)`);
      setTimeout(() => {
        ws.close();
        console.log("Done!");
        process.exit(0);
      }, 500);
    }
  });

  ws.on("error", (err) => {
    console.error(`Error: ${err.message}`);
    process.exit(1);
  });
}, DELAY * 1000);
