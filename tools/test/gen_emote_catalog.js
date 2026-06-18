// One-shot generator for data/emotes/catalog.json.
// Reads id+en-name pairs from .emote_pairs.json, applies per-ID overrides + rule
// fallbacks, and writes the enriched catalog. Re-runnable; idempotent.
//
// Tone rules (per [[feedback-emote-descriptions]]):
//   - OS-bubble (strikers/skins/mastery/holidays/in-OS lore): playful, short, BR slang OK.
//   - Real-world refs (colleges/streamers/real orgs/ranks/tactics): grounded, factual.
//   - No forced puns. Mark `_review: "needs-image"` on entries that need eyes-on.

const fs = require("fs");
const path = require("path");

const REPO = path.resolve(__dirname, "..", "..");
const SRC = path.join(__dirname, "_emote_pairs.json");
const OUT = path.join(REPO, "data", "emotes", "catalog.json");

const pairs = JSON.parse(fs.readFileSync(SRC, "utf8"));

// ──────────────────────────────────────────────────────────────────────────────
// Tag registry
// ──────────────────────────────────────────────────────────────────────────────
const TAGS = {
    // Strikers
    asher:        { en: "Asher",        pt: "Asher" },
    aimi:         { en: "Ai.Mi",        pt: "Ai.Mi" },
    atlas:        { en: "Atlas",        pt: "Atlas" },
    drekar:       { en: "Drek'ar",      pt: "Drek'ar" },
    dubu:         { en: "Dubu",         pt: "Dubu" },
    era:          { en: "Era",          pt: "Era" },
    estelle:      { en: "Estelle",      pt: "Estelle" },
    finii:        { en: "Finii",        pt: "Finii" },
    juliette:     { en: "Juliette",     pt: "Juliette" },
    juno:         { en: "Juno",         pt: "Juno" },
    kai:          { en: "Kai",          pt: "Kai" },
    kazan:        { en: "Kazan",        pt: "Kazan" },
    luna:         { en: "Luna",         pt: "Luna" },
    mako:         { en: "Mako",         pt: "Mako" },
    nao:          { en: "Nao",          pt: "Nao" },
    octavia:      { en: "Octavia",      pt: "Octavia" },
    rasmus:       { en: "Rasmus",       pt: "Rasmus" },
    rune:         { en: "Rune",         pt: "Rune" },
    vyce:         { en: "Vyce",         pt: "Vyce" },
    x:            { en: "X",            pt: "X" },
    zentaro:      { en: "Zentaro",      pt: "Zentaro" },

    // Emotion / mood
    reaction:     { en: "Reactions",    pt: "Reações" },
    cute:         { en: "Cute",         pt: "Fofo" },
    funny:        { en: "Funny",        pt: "Engraçado" },
    goofy:        { en: "Goofy",        pt: "Bobinho" },
    happy:        { en: "Happy",        pt: "Feliz" },
    sad:          { en: "Sad",          pt: "Triste" },
    sorry:        { en: "Sorry",        pt: "Desculpa" },
    angry:        { en: "Angry",        pt: "Bravo" },
    shocked:      { en: "Shocked",      pt: "Chocado" },
    disgusted:    { en: "Disgusted",    pt: "Enojado" },
    love:         { en: "Love",         pt: "Amor" },
    celebration:  { en: "Celebration",  pt: "Comemoração" },
    greeting:     { en: "Greeting",     pt: "Saudação" },
    friendly:     { en: "Friendly",     pt: "Amigável" },
    taunt:        { en: "Taunt",        pt: "Provocação" },
    thinking:     { en: "Thinking",     pt: "Pensativo" },
    sleepy:       { en: "Sleepy",       pt: "Sonolento" },
    approval:     { en: "Approval",     pt: "Aprovação" },
    disapproval:  { en: "Disapproval",  pt: "Desaprovação" },
    cool:         { en: "Cool",         pt: "Estiloso" },
    meme:         { en: "Meme",         pt: "Meme" },

    // Type / origin
    skin:         { en: "Skin",         pt: "Skin" },
    mastery:      { en: "Mastery",      pt: "Maestria" },
    holiday:      { en: "Holiday",      pt: "Evento" },
    collab:       { en: "Collab",       pt: "Colab" },
    streamer:     { en: "Streamer",     pt: "Streamer" },
    college:      { en: "College",      pt: "Universidade" },
    proleague:    { en: "Pro League",   pt: "Pro League" },
    tactic:       { en: "Tactics",      pt: "Táticas" },
    rank:         { en: "Rank",         pt: "Rank" },
    placeholder:  { en: "Placeholder",  pt: "Reservado" },
    pride:        { en: "Pride",        pt: "Orgulho" },
    blob:         { en: "Blob",         pt: "Blob" },
    discord:      { en: "Discord",      pt: "Discord" },
    lore:         { en: "Lore",         pt: "Lore" },
    community:    { en: "Community",    pt: "Comunidade" },

    // Theme
    summer:       { en: "Summer",       pt: "Verão" },
    halloween:    { en: "Halloween",    pt: "Halloween" },
    christmas:    { en: "Christmas",    pt: "Natal" },
    food:         { en: "Food",         pt: "Comida" },
    drink:        { en: "Drink",        pt: "Bebida" },
    tea:          { en: "Tea",          pt: "Chá" },
    coffee:       { en: "Coffee",       pt: "Café" },
    music:        { en: "Music",        pt: "Música" },
    fight:        { en: "Fight",        pt: "Luta" },
    magic:        { en: "Magic",        pt: "Magia" },
    cat:          { en: "Cat",          pt: "Gato" },
};

// ──────────────────────────────────────────────────────────────────────────────
// Per-ID overrides for OS-bubble entries.
// Format: id → [name_en?, name_pt, desc_en, desc_pt, tags[], reviewNote?]
// name_en defaults to existing en name if undefined.
// ──────────────────────────────────────────────────────────────────────────────
const O = {};
function set(id, opts) { O[id] = opts; }

// ── Strikers: Asher ──────────────────────────────────────────────────────────
set("EmoticonData_AsherCheer",    { ptName: "Asher Comemora",    en: "Asher cheering.",       pt: "É noiis!",                 tags: ["asher","reaction","celebration","happy"] });
set("EmoticonData_AsherDisgust",  { ptName: "Asher Julgando",    en: "Asher judging you.",    pt: "Asher te julgando.",       tags: ["asher","reaction","disgusted","disapproval"] });
set("EmoticonData_AsherPog",      { ptName: "Asher Pog",         en: "Poggers.",              pt: "Poggers.",                 tags: ["asher","reaction","shocked","meme"] });
set("EmoticonData_AsherPoint",    { ptName: "Asher Apontando",   en: "Asher pointing fingers.", pt: "Asher apontando o dedo.", tags: ["asher","reaction","taunt","funny"] });
set("EmoticonData_AsherShy",      { ptName: "Asher Tímido",      en: "Shy Asher.",            pt: "Asher tímido.",            tags: ["asher","reaction","cute","shy" in TAGS ? "shy" : "cute"].filter(t => TAGS[t]) });
set("EmoticonData_AsherTank",     { ptName: "Asher",             en: "Asher portrait.",       pt: "Retrato do Asher.",        tags: ["asher","reaction"] });

// ── Strikers: Ai.Mi ──────────────────────────────────────────────────────────
set("EmoticonData_AiMiCatSalad",  { ptName: "Ai.Mi Enojada",     en: "Ai.Mi disgusted.",      pt: "Ai.Q.Nojinho.",            tags: ["aimi","reaction","disgusted","cat"] });
set("EmoticonData_AimiCry",       { enName: "Cats Can Cry", ptName: "Gatas podem chorar", en: "Even cats cry.", pt: "Ai.Mi.Desculpa.", tags: ["aimi","reaction","sad","sorry","cute","cat"] });
set("EmoticonData_AiMiFree",      { ptName: "Gata de Graça",     en: "Free cat, take one.",   pt: "Ai.Mi Gatuita.",           tags: ["aimi","reaction","cute","goofy","cat"] });
set("EmoticonData_AiMiHello",     { ptName: "Ai.Mi Olá",         en: "Hii!",                  pt: "Oiiiiiii.",                tags: ["aimi","reaction","greeting","friendly","cute","cat"] });
set("EmoticonData_AiMiJam",       { ptName: "Ai.Mi Vibing",      en: "Beat-jamming cat.",     pt: "Tuts tuts tuts.",          tags: ["aimi","reaction","music","happy","funny","cat"] });
set("EmoticonData_AiMiNom",       { ptName: "Ai.Mi Mastigando",  en: "Nom nom.",              pt: "Nhom nhom.",               tags: ["aimi","reaction","cute","food","cat"] });
set("EmoticonData_AimiNoted",     { enName: "Noted", ptName: "Anotado", en: "Noted.",         pt: "Anotado.",                 tags: ["aimi","reaction","approval","funny","cat"] });
set("EmoticonData_AiMiPat",       { enName: "Head Pats", ptName: "Cafuné", en: "Pat the cat.", pt: "Cafuné na gatinha.",      tags: ["aimi","reaction","cute","love","cat"] });
set("EmoticonData_AiMiPlinking",  { ptName: "Ai.Mi Plink",       en: "Plink.",                pt: "Plink.",                   tags: ["aimi","reaction","funny","cat"], review: "needs-image" });
set("EmoticonData_AiMiPresent",   { ptName: "Ai.Mi Presente",    en: "Ai.Mi with a gift.",    pt: "Ai.Mi com um presente.",   tags: ["aimi","reaction","cute","cat"] });
set("EmoticonData_AiMiShocked",   { ptName: "Ai.Mi Chocada",     en: "Shocked cat.",          pt: "Gata chocada.",            tags: ["aimi","reaction","shocked","cat"] });
set("EmoticonData_AiMiShockedSalute", { ptName: "Ai.Mi Continência Chocada", en: "Salute, but shocked.", pt: "Continência, mas chocada.", tags: ["aimi","reaction","shocked","funny","cat"] });
set("EmoticonData_AiMiSmug",      { ptName: "Ai.Mi Maliciosa",   en: "Devious cat.",          pt: "Gata cheia de plano.",     tags: ["aimi","reaction","taunt","funny","cat"] });
set("EmoticonData_AiMiSpaceCat",  { ptName: "Ai.Mi Espacial",    en: "Space cat.",            pt: "Gata espacial.",           tags: ["aimi","reaction","cool","cat"] });
set("EmoticonData_AimiSweat",     { enName: "Sweaty Gamer Cat", ptName: "Gata Gamer Suada", en: "Sweaty gamer cat.", pt: "Gata gamer suada.", tags: ["aimi","reaction","funny","meme","cat"] });
set("EmoticonData_AiMiTank",      { ptName: "Ai.Mi",             en: "Ai.Mi portrait.",       pt: "Retrato da Ai.Mi.",        tags: ["aimi","reaction","cat"] });
set("EmoticonData_AiMiYapping",   { ptName: "Ai.Mi Tagarela",    en: "Yap yap yap.",          pt: "Blablabla.",               tags: ["aimi","reaction","funny","cat"] });

// ── Strikers: Atlas ──────────────────────────────────────────────────────────
set("EmoticonData_AtlasDefend",   { enName: "Shrimply Defend", ptName: "Defesa Simples", en: "Shrimply defending.", pt: "Simplesmente defendendo.", tags: ["atlas","reaction","approval","funny"] });
set("EmoticonData_AtlasHeal",     { enName: "Angel Atlas", ptName: "Atlas Anjo", en: "Angel mode.", pt: "Modo anjo.", tags: ["atlas","reaction","cute","magic"] });
set("EmoticonData_AtlasHeart",    { ptName: "Coração do Atlas", en: "Atlas heart.",         pt: "Coração do Atlas.",        tags: ["atlas","reaction","love","cute"] });
set("EmoticonData_AtlasLFG",      { ptName: "Atlas LFG",         en: "LFG!",                  pt: "Bora!",                    tags: ["atlas","reaction","celebration","happy"] });
set("EmoticonData_AtlasSip",      { ptName: "Atlas Tomando",     en: "Atlas sipping tea.",    pt: "Atlas tomando um chá.",    tags: ["atlas","reaction","drink","cool","funny"] });
set("EmoticonData_AtlasSweating", { ptName: "Atlas Suado",       en: "Sweating bullets.",     pt: "Suando frio.",             tags: ["atlas","reaction","funny","meme"] });
set("EmoticonData_AtlasTank",     { ptName: "Atlas",             en: "Atlas portrait.",       pt: "Retrato do Atlas.",        tags: ["atlas","reaction"] });
set("EmoticonData_AtlasThink",    { enName: "Use This", ptName: "Usa Isso", en: "Use this.", pt: "Usa isso.",                 tags: ["atlas","reaction","thinking","approval"] });
set("EmoticonData_AtlasThumbsUp", { enName: "Nice...", ptName: "Bom...", en: "Atlas approves.", pt: "Atlas aprovou.",         tags: ["atlas","reaction","approval","happy"] });

// ── Strikers: Drek'ar ────────────────────────────────────────────────────────
set("EmoticonData_DrekAngle",     { ptName: "Drek de Lado",      en: "Drek'ar side-eye.",     pt: "Drek'ar de lado.",         tags: ["drekar","reaction","cool"] });
set("EmoticonData_DrekarBlahBlah",{ enName: "Blah Blah Blah", ptName: "Blá Blá Blá", en: "Blah blah blah.", pt: "Blá blá blá.", tags: ["drekar","reaction","disapproval","funny"] });
set("EmoticonData_DrekarBusiness",{ enName: "Business Time", ptName: "Hora do Trabalho", en: "Boss-mode Drek'ar.", pt: "Drek'ar no expediente.", tags: ["drekar","reaction","cool","funny"] });
set("EmoticonData_DrekarDetective",{ ptName: "Detetive Drek'ar", en: "Detective Drek'ar.",   pt: "Detetive Drek'ar.",        tags: ["drekar","reaction","thinking","cool"] });
set("EmoticonData_DrekarHeadpat", { ptName: "Cafuné no Drek'ar", en: "Pat the demon.",        pt: "Cafuné no demônio.",       tags: ["drekar","reaction","cute","funny"] });
set("EmoticonData_DrekarPeace",   { enName: "Peace", ptName: "Paz", en: "Peace.",             pt: "Paz.",                     tags: ["drekar","reaction","cool"] });
set("EmoticonData_DrekarPresent", { ptName: "Drek'ar Presente",  en: "Drek'ar with a gift.",  pt: "Drek'ar com um presente.", tags: ["drekar","reaction","holiday","cute"] });
set("EmoticonData_DrekarSpeechless",{ ptName: "Drek'ar Sem Palavras", en: "Speechless.",     pt: "Sem palavras.",            tags: ["drekar","reaction","shocked","funny"] });
set("EmoticonData_DrekarTank",    { ptName: "Drek'ar",           en: "Drek'ar portrait.",     pt: "Retrato do Drek'ar.",      tags: ["drekar","reaction"] });

// ── Strikers: Dubu ───────────────────────────────────────────────────────────
set("EmoticonData_DubuBop",       { enName: "Big Bop Dubu", ptName: "Dubu Bop", en: "Dubu boop.", pt: "Bopzinho do Dubu.",    tags: ["dubu","reaction","cute","funny"] });
set("EmoticonData_DubuCheeky",    { enName: "Cheeky", ptName: "Atrevido", en: "Cheeky Dubu.", pt: "Dubu atrevido.",           tags: ["dubu","reaction","goofy","funny"] });
set("EmoticonData_DubuCheerAnimated",{ enName: "Show Me Them Paws", ptName: "Mostra as Patinhas", en: "Show me them paws.", pt: "Mostra as patinhas.", tags: ["dubu","reaction","celebration","cute"] });
set("EmoticonData_DubuCooking",   { ptName: "Dubu Cozinhando",   en: "He's cooking.",         pt: "Tá cozinhando.",           tags: ["dubu","reaction","cute","food","goofy"] });
set("EmoticonData_DubuCurious",   { ptName: "Dubu Curioso",      en: "Curious Dubu.",         pt: "Dubu curioso.",            tags: ["dubu","reaction","thinking","cute"] });
set("EmoticonData_DubuHuh",       { enName: "HUH?!", ptName: "HÃ?!", en: "Huh?!",             pt: "Hã?!",                     tags: ["dubu","reaction","shocked","funny"] });
set("EmoticonData_DubuIceCream",  { enName: "Melted Ice Cream", ptName: "Sorvete Derretido", en: "Melted ice cream.", pt: "Sorvete derretido.", tags: ["dubu","reaction","sad","food","cute"] });
set("EmoticonData_DubuOne",       { enName: "You're Number One!", ptName: "Você é o Número 1!", en: "You're number one!", pt: "Você é o número 1!", tags: ["dubu","reaction","approval","cute","celebration"] });
set("EmoticonData_DubuPanicked",  { ptName: "Dubu em Pânico",    en: "Panicked Dubu.",        pt: "Dubu em pânico.",          tags: ["dubu","reaction","shocked","funny"] });
set("EmoticonData_DubuShocked",   { ptName: "Dubu Chocado",      en: "Shocked Dubu.",         pt: "Dubu chocado.",            tags: ["dubu","reaction","shocked"] });
set("EmoticonData_DubuTank",      { ptName: "Dubu",              en: "Dubu portrait.",        pt: "Retrato do Dubu.",         tags: ["dubu","reaction"] });
set("EmoticonData_DubuYas",       { enName: "Fabulous!", ptName: "Maravilhoso!", en: "Fabulous!", pt: "Maravilhoso!",         tags: ["dubu","reaction","celebration","happy","funny"] });

// ── Strikers: Era ────────────────────────────────────────────────────────────
set("EmoticonData_EraBocchi",     { enName: "Era Awkward", ptName: "Era Constrangida", en: "Awkward Era.", pt: "Era encabulada.", tags: ["era","reaction","cute","funny","meme"] });
set("EmoticonData_EraIsThis",     { enName: "Is this a butterfly?", ptName: "Isso é uma borboleta?", en: "Is this a butterfly?", pt: "Isso é uma borboleta?", tags: ["era","reaction","meme","funny"] });
set("EmoticonData_EraRainDrop",   { enName: "All Rain, No Tears", ptName: "Só Chuva, Sem Lágrimas", en: "All rain, no tears.", pt: "Só chuva, sem lágrima.", tags: ["era","reaction","sad","cool"] });
set("EmoticonData_EraSorry",      { ptName: "Era Foi Mal",       en: "Era's sorry.",          pt: "Era foi mal.",             tags: ["era","reaction","sorry","sad"] });
set("EmoticonData_EraTank",       { ptName: "Era",               en: "Era portrait.",         pt: "Retrato da Era.",          tags: ["era","reaction","cool"] });
set("EmoticonData_EraUwu",        { ptName: "Era Uwu",           en: "Era uwu.",              pt: "Era uwu.",                 tags: ["era","reaction","cute","meme"] });
set("EmoticonData_EraWiltedPoppy",{ ptName: "Era Papoula Murcha",en: "Wilted poppy Era.",     pt: "Era com a papoula murcha.",tags: ["era","reaction","sad"] });

// ── Strikers: Estelle ────────────────────────────────────────────────────────
set("EmoticonData_EstelleFacepalm",{ ptName: "Estelle Facepalm", en: "Estelle facepalm.",     pt: "Estelle facepalm.",        tags: ["estelle","reaction","disapproval","funny"] });
set("EmoticonData_EstelleGloat",  { ptName: "Estelle Convencida", en: "Gloating Estelle.",    pt: "Estelle se achando.",      tags: ["estelle","reaction","taunt","funny"] });
set("EmoticonData_EstelleTank",   { ptName: "Estelle",           en: "Estelle portrait.",     pt: "Retrato da Estelle.",      tags: ["estelle","reaction"] });

// ── Strikers: Finii ──────────────────────────────────────────────────────────
set("EmoticonData_FiniiCocoa",    { enName: "Hot Cocoa", ptName: "Chocolate Quente", en: "Hot cocoa Finii.", pt: "Finii com chocolate quente.", tags: ["finii","reaction","cute","drink","holiday"] });
set("EmoticonData_FiniiGrin",     { ptName: "Finii Sorriso",     en: "Finii grin.",           pt: "Sorrisão da Finii.",       tags: ["finii","reaction","happy","cute"] });
set("EmoticonData_FiniiNo",       { enName: "No.", ptName: "Não.", en: "No.",                  pt: "Não.",                     tags: ["finii","reaction","disapproval","funny"] });
set("EmoticonData_FiniiSmug",     { ptName: "Finii Maliciosa",   en: "Smug Finii.",           pt: "Finii maliciosa.",         tags: ["finii","reaction","taunt","funny"] });
set("EmoticonData_FiniiTank",     { ptName: "Finii",             en: "Finii portrait.",       pt: "Retrato da Finii.",        tags: ["finii","reaction"] });
set("EmoticonData_FiniiTeehee",   { enName: "Teehee", ptName: "Hihihi", en: "Teehee.",         pt: "Hihihi.",                  tags: ["finii","reaction","cute","goofy"] });
set("EmoticonData_FiniiTired",    { enName: "Tired", ptName: "Cansada", en: "Tired Finii.",   pt: "Finii cansada.",           tags: ["finii","reaction","sleepy"] });
set("EmoticonData_FiniiZoom",     { ptName: "Finii Voando",      en: "Finii zooming by.",     pt: "Finii passando voando.",   tags: ["finii","reaction","cool","funny"] });

// ── Strikers: Juliette ───────────────────────────────────────────────────────
set("EmoticonData_JulietteAyaya", { ptName: "Juliette Ayaya",    en: "Juliette ayaya.",       pt: "Juliette ayaya.",          tags: ["juliette","reaction","cute","meme"] });
set("EmoticonData_JulietteComfy", { ptName: "Juliette Confortável", en: "Comfy Juli.",        pt: "Juli confortável.",        tags: ["juliette","reaction","cute","sleepy"] });
set("EmoticonData_JulietteCool",  { enName: "Pretty Cool Juliette", ptName: "Juliette Estilosa", en: "Pretty cool Juli.", pt: "Juli estilosa.", tags: ["juliette","reaction","cool"] });
set("EmoticonData_JulietteCopium",{ enName: "Copium", ptName: "Copium", en: "Copium.",        pt: "Copium.",                  tags: ["juliette","reaction","sad","meme"] });
set("EmoticonData_JulietteDefeated",{ ptName: "Juliette Derrotada", en: "Defeated Juli.",     pt: "Juli derrotada.",          tags: ["juliette","reaction","sad"] });
set("EmoticonData_JulietteGG",    { ptName: "Juliette GG",       en: "GG.",                   pt: "GG.",                      tags: ["juliette","reaction","approval","celebration"] });
set("EmoticonData_JulietteHeart", { enName: "Big Heart Juliette", ptName: "Coração da Juli", en: "Heart from Juli.", pt: "Coração da Juli.", tags: ["juliette","reaction","love","cute"] });
set("EmoticonData_JulietteLightsOut",{ enName: "Lights Out", ptName: "Apagou as Luzes", en: "Lights out.", pt: "Apagou as luzes.", tags: ["juliette","reaction","taunt","cool"] });
set("EmoticonData_JuliettePoint", { ptName: "Juliette Aponta",   en: "Juli pointing.",        pt: "Juli apontando.",          tags: ["juliette","reaction","taunt"] });
set("EmoticonData_JuliettePunch", { ptName: "Soco da Juli",      en: "Juli punching.",        pt: "Soco da Juli.",            tags: ["juliette","reaction","fight","cool"] });
set("EmoticonData_JulietteRave",  { ptName: "Juli na Rave",      en: "Juli at the rave.",     pt: "Juli na rave.",            tags: ["juliette","reaction","music","celebration","happy"] });
set("EmoticonData_JulietteThumbsUp",{ ptName: "Juliette Joinha", en: "Juli thumbs up.",       pt: "Joinha da Juli.",          tags: ["juliette","reaction","approval","happy"] });
set("EmoticonData_JulietteToastRun",{ ptName: "Juli no Toast Run", en: "Toast-run Juli.",     pt: "Juli no toast run.",       tags: ["juliette","reaction","funny","meme"], review: "needs-image" });
set("EmoticonData_JulietteVibe",  { enName: "Just Vibing", ptName: "Só Vibing", en: "Just vibing.", pt: "Só vibing.",          tags: ["juliette","reaction","music","cool","happy"] });
set("EmoticonData_JuliTank",      { ptName: "Juli",              en: "Juliette portrait.",    pt: "Retrato da Juli.",         tags: ["juliette","reaction"] });

// ── Strikers: Juno ───────────────────────────────────────────────────────────
set("EmoticonData_JunoBop",       { enName: "Big Bop Juno", ptName: "Juno Bop", en: "Juno boop.", pt: "Bopzinho da Juno.",    tags: ["juno","reaction","cute","funny"] });
set("EmoticonData_JunoCute",      { ptName: "Juno Fofa",         en: "Cute Juno.",            pt: "Juno fofa.",               tags: ["juno","reaction","cute"] });
set("EmoticonData_JunoDevious",   { ptName: "Juno Maliciosa",    en: "Devious Juno.",         pt: "Juno cheia de plano.",     tags: ["juno","reaction","taunt","funny"] });
set("EmoticonData_JunoFight",     { enName: "Angry Juno", ptName: "Juno Brava", en: "Angry Juno.", pt: "Juno brava.",         tags: ["juno","reaction","angry","fight"] });
set("EmoticonData_JunoGawk",      { ptName: "Juno Boquiaberta",  en: "Gawking Juno.",         pt: "Juno boquiaberta.",        tags: ["juno","reaction","shocked","funny"] });
set("EmoticonData_JunoGiggle",    { ptName: "Juno Rindo",        en: "Giggling Juno.",        pt: "Juno rindo.",              tags: ["juno","reaction","happy","cute"] });
set("EmoticonData_JunoShy",       { enName: "Super Shy Juno", ptName: "Juno Tímida", en: "Super shy Juno.", pt: "Juno super tímida.", tags: ["juno","reaction","cute"] });
set("EmoticonData_JunoSleep",     { enName: "Nap Time Juno", ptName: "Hora do Cochilo", en: "Nap-time Juno.", pt: "Juno cochilando.", tags: ["juno","reaction","sleepy","cute"] });
set("EmoticonData_JunoSnackTime", { ptName: "Hora do Lanche",    en: "Snack-time Juno.",      pt: "Juno na hora do lanche.",  tags: ["juno","reaction","food","cute"] });
set("EmoticonData_JunoStarry",    { enName: "Starry Eyed Juno", ptName: "Olhinhos Brilhando", en: "Stars in her eyes.", pt: "Olhinhos brilhando.", tags: ["juno","reaction","cute","happy"] });
set("EmoticonData_JunoStraw",     { ptName: "Juno Canudinho",    en: "Juno with a straw.",    pt: "Juno com canudinho.",      tags: ["juno","reaction","cute","drink"] });
set("EmoticonData_JunoSurrender", { enName: "I Surrender", ptName: "Eu Desisto", en: "I surrender.", pt: "Eu desisto.",       tags: ["juno","reaction","sad","funny"] });
set("EmoticonData_JunoTank",      { ptName: "Juno",              en: "Juno portrait.",        pt: "Retrato da Juno.",         tags: ["juno","reaction"] });
set("EmoticonData_JunoWahhh",     { ptName: "Juno Wahhh",        en: "Wahhh!",                pt: "Wahhh!",                   tags: ["juno","reaction","sad","cute"] });

// ── Strikers: Kai ────────────────────────────────────────────────────────────
set("EmoticonData_KaiChristmasExpansion",{ ptName: "Kai de Natal", en: "Christmas Kai.",     pt: "Kai de Natal.",             tags: ["kai","skin","holiday","christmas"] });
set("EmoticonData_KaiGlamour",    { enName: "Glamour Shot Kai", ptName: "Kai Glamour", en: "Glamour-shot Kai.", pt: "Kai no glamour.", tags: ["kai","reaction","cool"] });
set("EmoticonData_KaiShambles",   { enName: "Kai in Shambles", ptName: "Kai Destruída", en: "Kai in shambles.", pt: "Kai destruída.", tags: ["kai","reaction","sad","funny"] });
set("EmoticonData_KaiTank",       { ptName: "Kai",               en: "Kai portrait.",         pt: "Retrato da Kai.",          tags: ["kai","reaction"] });

// ── Strikers: Kazan ──────────────────────────────────────────────────────────
set("EmoticonData_KasanDotingBrother",{ ptName: "Irmão Coruja Kazan", en: "Doting brother Kazan.", pt: "Kazan irmão coruja.", tags: ["kazan","reaction","cute","lore"] });
set("EmoticonData_KazanCandyCane",{ ptName: "Kazan Bengala Doce",en: "Candy-cane Kazan.",     pt: "Kazan com bengala doce.",  tags: ["kazan","skin","holiday","christmas"] });
set("EmoticonData_KazanTank",     { ptName: "Kazan",             en: "Kazan portrait.",       pt: "Retrato do Kazan.",        tags: ["kazan","reaction"] });

// ── Strikers: Luna ───────────────────────────────────────────────────────────
set("EmoticonData_LunaBoom",      { enName: "KA-BOOM!", ptName: "KABUM!", en: "Ka-boom!",     pt: "Kabum!",                   tags: ["luna","reaction","fight","cool"] });
set("EmoticonData_LunaCry",       { enName: "WAHH!", ptName: "WAHH!", en: "Wahh!",            pt: "Wahh!",                    tags: ["luna","reaction","sad","cute"] });
set("EmoticonData_LunaGlasses",   { enName: "The Power of Science!", ptName: "O Poder da Ciência!", en: "Power of science!", pt: "O poder da ciência!", tags: ["luna","reaction","thinking","cool","funny"] });
set("EmoticonData_LunaPeace",     { ptName: "Luna Paz",          en: "Luna peace.",           pt: "Luna na paz.",             tags: ["luna","reaction","cool"] });
set("EmoticonData_LunaRun",       { enName: "Rocket Run", ptName: "Corrida de Foguete", en: "Rocket run.", pt: "Corrida de foguete.", tags: ["luna","reaction","cool","funny"] });
set("EmoticonData_LunaTank",      { ptName: "Luna",              en: "Luna portrait.",        pt: "Retrato da Luna.",         tags: ["luna","reaction"] });
set("EmoticonData_LunaWizard",    { enName: "See The Future", ptName: "Ver o Futuro", en: "See the future.", pt: "Ver o futuro.", tags: ["luna","reaction","magic","cool"] });

// ── Strikers: Mako ───────────────────────────────────────────────────────────
set("EmoticonData_MakoBadHairDay",{ ptName: "Mako Cabelo Ruim",  en: "Bad hair day.",         pt: "Dia de cabelo ruim.",      tags: ["mako","reaction","funny","sad"] });
set("EmoticonData_MakoCheers",    { ptName: "Mako Saúde",        en: "Mako cheers.",          pt: "Mako brindando.",          tags: ["mako","reaction","celebration","drink"] });
set("EmoticonData_MakoDango",     { ptName: "Mako Dango",        en: "Mako with dango.",      pt: "Mako com dango.",          tags: ["mako","reaction","food","cute"] });
set("EmoticonData_MakoOhno",      { ptName: "Mako Ah Não",       en: "Oh no.",                pt: "Ah não.",                  tags: ["mako","reaction","sad","funny"] });
set("EmoticonData_MakoTank",      { ptName: "Mako",              en: "Mako portrait.",        pt: "Retrato da Mako.",         tags: ["mako","reaction"] });

// ── Strikers: Nao ────────────────────────────────────────────────────────────
set("EmoticonData_NaoCheer",      { ptName: "Nao Comemora",      en: "Nao cheering.",         pt: "Nao comemorando.",         tags: ["nao","reaction","celebration","happy"] });
set("EmoticonData_NaoNaughtyList",{ enName: "Nao Noted", ptName: "Nao Anotou", en: "Nao noted you.", pt: "Nao te anotou.",     tags: ["nao","reaction","funny","holiday","christmas"] });
set("EmoticonData_NaoRest",       { ptName: "Nao Descansando",   en: "Nao resting.",          pt: "Nao descansando.",         tags: ["nao","reaction","sleepy"] });
set("EmoticonData_NaoSleep",      { ptName: "Nao Dormindo",      en: "Nao sleeping.",         pt: "Nao dormindo.",            tags: ["nao","reaction","sleepy","cute"] });
set("EmoticonData_NaoTank",       { ptName: "Nao",               en: "Nao portrait.",         pt: "Retrato da Nao.",          tags: ["nao","reaction"] });
set("EmoticonData_NaoUnamused",   { ptName: "Nao Sem Graça",     en: "Unamused Nao.",         pt: "Nao sem graça.",           tags: ["nao","reaction","disapproval"] });

// ── Strikers: Octavia ────────────────────────────────────────────────────────
set("EmoticonData_OctaviaCheers", { ptName: "Octavia Saúde",     en: "Octavia cheers.",       pt: "Octavia brindando.",       tags: ["octavia","reaction","celebration","drink"] });
set("EmoticonData_OctaviaHeadphones",{ ptName: "Octavia de Fone",en: "Octavia with headphones.", pt: "Octavia de fone.",      tags: ["octavia","reaction","music","cool"] });
set("EmoticonData_OctaviaJump",   { ptName: "Octavia Pulando",   en: "Octavia jumping.",      pt: "Octavia pulando.",         tags: ["octavia","reaction","happy"] });
set("EmoticonData_OctaviaRun",    { enName: "Zoom", ptName: "Zoom", en: "Zoom.",              pt: "Zoom.",                    tags: ["octavia","reaction","cool","funny"] });
set("EmoticonData_OctaviaTank",   { ptName: "Octavia",           en: "Octavia portrait.",     pt: "Retrato da Octavia.",      tags: ["octavia","reaction"] });

// ── Strikers: Rasmus ─────────────────────────────────────────────────────────
set("EmoticonData_RasmusAngry",   { ptName: "Rasmus Bravo",      en: "Angry Rasmus.",         pt: "Rasmus bravo.",            tags: ["rasmus","reaction","angry"] });
set("EmoticonData_RasmusBusiness",{ enName: "Work Hard, Play Hard", ptName: "Trabalha Forte, Joga Forte", en: "Work hard, play hard.", pt: "Trabalha forte, joga forte.", tags: ["rasmus","reaction","cool"] });
set("EmoticonData_RasmusCoffee",  { ptName: "Rasmus Café",       en: "Coffee Rasmus.",        pt: "Rasmus com café.",         tags: ["rasmus","reaction","drink","coffee","cute"] });
set("EmoticonData_RasmusMail",    { ptName: "Rasmus Correio",    en: "Mail-time Rasmus.",     pt: "Rasmus carteiro.",         tags: ["rasmus","reaction","cute","funny"] });
set("EmoticonData_RasmusPray",    { enName: "Pray", ptName: "Reza", en: "Pray.",              pt: "Reza.",                    tags: ["rasmus","reaction","thinking"] });
set("EmoticonData_RasmusShocked", { enName: "ARE YOU SERIOUS?!?!", ptName: "TÁ DE BRINCADEIRA?!", en: "Are you serious?!", pt: "Tá de brincadeira?!", tags: ["rasmus","reaction","shocked","angry"] });
set("EmoticonData_RasmusTank",    { ptName: "Rasmus",            en: "Rasmus portrait.",      pt: "Retrato do Rasmus.",       tags: ["rasmus","reaction"] });

// ── Strikers: Rune ───────────────────────────────────────────────────────────
set("EmoticonData_RuneClone",     { enName: "Let the Evil Consume", ptName: "Que o Mal Consuma", en: "Let the evil consume.", pt: "Que o mal consuma.", tags: ["rune","reaction","cool","magic"] });
set("EmoticonData_RuneCry",       { enName: "It's raining...", ptName: "Tá chovendo...", en: "It's raining...", pt: "Tá chovendo...", tags: ["rune","reaction","sad"] });
set("EmoticonData_RuneDespair",   { enName: "Despair", ptName: "Desespero", en: "Despair.",   pt: "Desespero.",               tags: ["rune","reaction","sad"] });
set("EmoticonData_RuneFeelRelieved",{ ptName: "Rune Aliviado",   en: "Relieved Rune.",        pt: "Rune aliviado.",           tags: ["rune","reaction","happy"] });
set("EmoticonData_RuneHeart",     { ptName: "Coração do Rune",   en: "Rune heart.",           pt: "Coração do Rune.",         tags: ["rune","reaction","love","cute"] });
set("EmoticonData_RuneOrbing",    { ptName: "Rune Orbando",      en: "Rune orbing.",          pt: "Rune orbando.",            tags: ["rune","reaction","funny","magic"] });
set("EmoticonData_RunePoor",      { enName: "No Money", ptName: "Sem Dinheiro", en: "No money.", pt: "Sem grana.",            tags: ["rune","reaction","sad","funny"] });
set("EmoticonData_RuneSalute",    { ptName: "Continência do Rune", en: "Rune salute.",        pt: "Continência do Rune.",     tags: ["rune","reaction","greeting","friendly"] });
set("EmoticonData_RuneTank",      { ptName: "Rune",              en: "Rune portrait.",        pt: "Retrato do Rune.",         tags: ["rune","reaction"] });
set("EmoticonData_RuneV",         { enName: "V for Victory!", ptName: "V de Vitória!", en: "V for victory!", pt: "V de vitória!", tags: ["rune","reaction","celebration","happy"] });
set("EmoticonData_RuneYouAreMe",  { enName: "You Are Me!", ptName: "Você é Eu!", en: "You are me!", pt: "Você é eu!",          tags: ["rune","reaction","funny","meme"] });

// ── Strikers: Vyce ───────────────────────────────────────────────────────────
set("EmoticonData_VyceCheers",    { ptName: "Vyce Saúde",        en: "Vyce cheers.",          pt: "Vyce brindando.",          tags: ["vyce","reaction","celebration","drink"] });
set("EmoticonData_VyceDrake_1",   { enName: "Vyce Rejected", ptName: "Vyce Rejeita", en: "Vyce rejecting.", pt: "Vyce rejeitando.", tags: ["vyce","reaction","disapproval","meme"] });
set("EmoticonData_VyceDrake_2",   { enName: "Vyce Approved", ptName: "Vyce Aprovou", en: "Vyce approving.", pt: "Vyce aprovou.", tags: ["vyce","reaction","approval","meme"] });
set("EmoticonData_VyceHolidayStar",{ ptName: "Vyce Estrela Natalina", en: "Holiday-star Vyce.", pt: "Vyce com estrela natalina.", tags: ["vyce","skin","holiday","christmas"] });
set("EmoticonData_VyceJump",      { ptName: "Vyce Pulando",      en: "Vyce jumping.",         pt: "Vyce pulando.",            tags: ["vyce","reaction","happy"] });
set("EmoticonData_VyceSweat",     { enName: "Sweating", ptName: "Suando", en: "Vyce sweating.", pt: "Vyce suando.",           tags: ["vyce","reaction","funny","meme"] });
set("EmoticonData_VyceTank2",     { ptName: "Vyce",              en: "Vyce portrait.",        pt: "Retrato do Vyce.",         tags: ["vyce","reaction"] });
set("EmoticonData_VyceWantsYou",  { ptName: "Vyce Quer Você",    en: "Vyce wants you.",       pt: "Vyce quer você.",          tags: ["vyce","reaction","taunt","cool"] });

// ── Strikers: X ──────────────────────────────────────────────────────────────
set("EmoticonData_XDemonHours",   { ptName: "X em Hora do Demônio", en: "X demon hours.",     pt: "X em hora do demônio.",    tags: ["x","reaction","cool","angry"] });
set("EmoticonData_XGigachad",     { ptName: "GigaChad X",        en: "GigaChad X.",           pt: "GigaChad X.",              tags: ["x","reaction","meme","cool"] });
set("EmoticonData_XMistletoe",    { enName: "Merry X-Mas", ptName: "Feliz Natal do X", en: "X wants a kiss?", pt: "Beijinho do X?", tags: ["x","skin","holiday","christmas","funny","love"] });
set("EmoticonData_XRage",         { ptName: "X Furioso",         en: "X is tilted.",          pt: "X tiltou.",                tags: ["x","reaction","angry","meme"] });
set("EmoticonData_XRead",         { ptName: "X Lendo",           en: "X reading you.",        pt: "X te lendo.",              tags: ["x","reaction","taunt","cool"] });
set("EmoticonData_XTank",         { enName: "X Tank", ptName: "X", en: "X portrait.",         pt: "Retrato do X.",            tags: ["x","reaction"] });
set("EmoticonData_XWheez",        { enName: "X Wheeze", ptName: "X Engasgando", en: "X wheezing.", pt: "X engasgando de rir.", tags: ["x","reaction","funny","happy"] });

// ── Strikers: Zentaro ────────────────────────────────────────────────────────
set("EmoticonData_ZentaroCryMask",{ enName: "Crying Behind the Mask", ptName: "Chorando Atrás da Máscara", en: "Crying behind the mask.", pt: "Chorando atrás da máscara.", tags: ["zentaro","reaction","sad"] });
set("EmoticonData_ZentaroDeadge", { enName: "RIP", ptName: "RIP", en: "RIP.",                pt: "RIP.",                     tags: ["zentaro","reaction","sad","meme"] });

// ── Skins ────────────────────────────────────────────────────────────────────
set("EmoticonData_AgentJuno",     { ptName: "Agente Juno",       en: "Agent Juno.",           pt: "Junos de preto.",          tags: ["juno","skin","cool","funny"] });
set("EmoticonData_AhiAsher1",     { ptName: "Ahi Asher",         en: "Asher served sushi-style.", pt: "Asher temaki.",        tags: ["asher","skin","food","cute"] });
set("EmoticonData_AhiAsher2",     { ptName: "Ahi Asher 2",       en: "Asher sushi, take two.", pt: "Asher temaki, parte 2.",  tags: ["asher","skin","food","cute"] });
set("EmoticonData_AhiEstelle",    { ptName: "Ahi Estelle",       en: "Estelle sushi-style.",  pt: "Estelle versão sushi.",    tags: ["estelle","skin","food","cute"] });
set("EmoticonData_AhiKai",        { ptName: "Ahi Kai",           en: "Kai sushi-style.",      pt: "Kai versão sushi.",        tags: ["kai","skin","food","cute"] });
set("EmoticonData_DJAtlas",       { enName: "Beat Drop", ptName: "Beat Drop", en: "DJ Atlas drops the beat.", pt: "DJ Atlas no drop.", tags: ["atlas","skin","music","cool"] });
set("EmoticonData_DojoAimi",      { ptName: "Dojo Ai.Mi",        en: "Dojo Ai.Mi.",           pt: "Dojo Ai.Mi.",              tags: ["aimi","skin","cool","cat"] });
set("EmoticonData_DojoDubu",      { ptName: "Dojo Dubu",         en: "Dojo Dubu.",            pt: "Dojo Dubu.",               tags: ["dubu","skin","cool"] });
set("EmoticonData_DojoMako",      { ptName: "Dojo Mako",         en: "Dojo Mako.",            pt: "Dojo Mako.",               tags: ["mako","skin","cool"] });
set("EmoticonData_EternalFlameDubu",{ ptName: "Dubu Chama Eterna", en: "Eternal-flame Dubu.", pt: "Dubu chama eterna.",      tags: ["dubu","skin","fight","cool"] });
set("EmoticonData_EuroCupEstelle",{ ptName: "Estelle EuroCup",   en: "EuroCup Estelle.",      pt: "Estelle EuroCup.",         tags: ["estelle","skin","holiday"] });
set("EmoticonData_FrostfireTeamTsumTsum",{ enName: "Frostfire Blobbos", ptName: "Blobbos do Frostfire", en: "Frostfire blobbos.", pt: "Blobbos do Frostfire.", tags: ["proleague","blob","cute","skin"] });
set("EmoticonData_GardenerAtlas", { ptName: "Atlas Jardineiro",  en: "Gardener Atlas.",       pt: "Atlas jardineiro.",        tags: ["atlas","skin","cute"] });
set("EmoticonData_GlitchWitch",   { ptName: "Bruxa Glitch",      en: "Glitch Witch.",         pt: "Bruxa Glitch.",            tags: ["skin","magic","cool"], review: "needs-image" });
set("EmoticonData_IdolAimiHeart", { enName: "With Love", ptName: "Com Amor", en: "Idol Ai.Mi, with love.", pt: "Idol Ai.Mi, com amor.", tags: ["aimi","skin","love","cute","music"] });
set("EmoticonData_OCEAiMi",       { enName: "OCEAi.Mi", ptName: "OCEAi.Mi", en: "Ocean Ai.Mi.", pt: "Ai.Mi do oceano.",       tags: ["aimi","skin","cute","cat"] });
set("EmoticonData_PixelJuliette", { ptName: "Juliette Pixel",    en: "Pixel Juliette.",       pt: "Juliette pixel.",          tags: ["juliette","skin","cute"] });
set("EmoticonData_PixelSonii",    { ptName: "Sonii Pixel",       en: "Pixel Sonii.",          pt: "Sonii pixel.",             tags: ["skin","streamer","collab","cute","community"] });
set("EmoticonData_SummerAsher",   { enName: "Summer Splash Asher", ptName: "Asher de Verão", en: "Beach-day Asher.",         pt: "Asher na praia.",          tags: ["asher","skin","summer","cute"] });
set("EmoticonData_SummerDubu",    { enName: "Summer Splash Dubu", ptName: "Dubu de Verão", en: "Beach-day Dubu.",            pt: "Dubu na praia.",           tags: ["dubu","skin","summer","cute"] });
set("EmoticonData_SummerEstelle", { enName: "Summer Splash Estelle", ptName: "Estelle de Verão", en: "Beach-day Estelle.",   pt: "Estelle na praia.",        tags: ["estelle","skin","summer","cute"] });
set("EmoticonData_SummerJuliette",{ enName: "Summer Splash Juliette", ptName: "Juliette de Verão", en: "Beach-day Juli.",    pt: "Juli na praia.",           tags: ["juliette","skin","summer","cute","happy"] });
set("EmoticonData_SummerJuno",    { enName: "Summer Splash Juno", ptName: "Juno de Verão", en: "Beach-day Juno.",            pt: "Juno na praia.",           tags: ["juno","skin","summer","cute"] });
set("EmoticonData_SummerX",       { enName: "Summer Splash X", ptName: "X de Verão", en: "Beach-day X.",                     pt: "X na praia.",              tags: ["x","skin","summer","funny"] });
set("EmoticonData_TeaTimeDubu",   { enName: "Welcome", ptName: "Bem-vindo", en: "Tea-time Dubu welcomes.", pt: "Dubu do chá te recebe.", tags: ["dubu","skin","tea","cute","friendly"] });
set("EmoticonData_TeaTimeFinii",  { enName: "Pew Pew", ptName: "Piu Piu", en: "Tea-time Finii.", pt: "Finii do chá.",        tags: ["finii","skin","tea","cute","funny"] });
set("EmoticonData_TeaTimeMatcha", { enName: "Matcha", ptName: "Matcha", en: "Matcha.",          pt: "Matcha.",                  tags: ["skin","tea","drink"] });
set("EmoticonData_TeaTimeMilk",   { enName: "Milk Tea", ptName: "Chá com Leite", en: "Milk tea.", pt: "Chá com leite.",       tags: ["skin","tea","drink"] });
set("EmoticonData_TeaTimePumpkin",{ enName: "Pumpkin Spice", ptName: "Pumpkin Spice", en: "Pumpkin spice.", pt: "Pumpkin spice.", tags: ["skin","tea","drink","holiday"] });
set("EmoticonData_TeaTimeTaro",   { enName: "Taro", ptName: "Taro", en: "Taro.",              pt: "Taro.",                    tags: ["skin","tea","drink"] });
set("EmoticonData_OniRelease",    { enName: "Menace", ptName: "Ameaça", en: "Oni unleashed.", pt: "Drek'ar solto.",           tags: ["drekar","skin","angry","cool"] });

// ── Halloween ────────────────────────────────────────────────────────────────
set("EmoticonData_Halloween_Duboo", { enName: "Boo!", ptName: "Bu!", en: "Boo!",              pt: "Bu!",                      tags: ["dubu","skin","holiday","halloween","cute","funny"] });
set("EmoticonData_Halloween_Era_Coffin",{ enName: "Coffinge", ptName: "Coffinge", en: "Coffin-dance Era.", pt: "Era na dança do caixão.", tags: ["era","skin","holiday","halloween","meme","funny"] });
set("EmoticonData_Halloween_Estelle_Nurse",{ enName: "It Won't Hurt... Much!", ptName: "Não Vai Doer... Muito!", en: "It won't hurt... much.", pt: "Não vai doer... muito.", tags: ["estelle","skin","holiday","halloween","funny"] });
set("EmoticonData_Halloween_Juno_Clown",{ enName: "Clown Plays", ptName: "Jogadas de Palhaço", en: "Clown plays.", pt: "Jogadas de palhaço.", tags: ["juno","skin","holiday","halloween","funny","meme"] });
set("EmoticonData_Halloween_XWerewolf",{ enName: "ARGH!", ptName: "ARGH!", en: "Werewolf X.",  pt: "X lobisomem.",            tags: ["x","skin","holiday","halloween","funny"] });

// ── Tactics ──────────────────────────────────────────────────────────────────
set("EmoticonData_Tactics_EnergyBurst",{ enName: "Energy Burst!", ptName: "Energia!", en: "Burst incoming.", pt: "Energia chegando.", tags: ["tactic","reaction"] });
set("EmoticonData_Tactics_FallBack",{ enName: "Fall Back!", ptName: "Recua!", en: "Fall back!", pt: "Recua!",                 tags: ["tactic","reaction"] });
set("EmoticonData_Tactics_GetOrbs",{ enName: "Get Orbs!", ptName: "Pega as Esferas!", en: "Get the orbs.", pt: "Pega as esferas.", tags: ["tactic","reaction"] });
set("EmoticonData_Tactics_Help",  { enName: "Help!", ptName: "Ajuda!", en: "Need help.",       pt: "Preciso de ajuda.",        tags: ["tactic","reaction","sad"] });
set("EmoticonData_Tactics_KO",    { enName: "KO!", ptName: "Nocaute!", en: "Going for KO.",   pt: "Vai pro nocaute.",         tags: ["tactic","reaction","celebration"] });
set("EmoticonData_Tactics_LetMeDefend",{ enName: "Let Me Defend!", ptName: "Deixa Eu Defender!", en: "Let me defend.", pt: "Deixa eu defender.", tags: ["tactic","reaction"] });
set("EmoticonData_Tactics_Pass",  { enName: "Pass!", ptName: "Passa!", en: "Pass the orb.",   pt: "Passa a esfera.",          tags: ["tactic","reaction"] });
set("EmoticonData_Tactics_Sorry", { enName: "Sorry!", ptName: "Foi Mal!", en: "My bad.",      pt: "Foi mal.",                 tags: ["tactic","reaction","sorry"] });
set("EmoticonData_Tactics_SpreadOut",{ enName: "Spread Out!", ptName: "Se Espalhem!", en: "Spread out.", pt: "Se espalha.",   tags: ["tactic","reaction"] });

// ── Blob / Pride ─────────────────────────────────────────────────────────────
set("EmoticonData_BlobAsexual",   { ptName: "Blob Assexual",     en: "Asexual pride blob.",   pt: "Blob da bandeira assexual.", tags: ["blob","pride","love"] });
set("EmoticonData_BlobBisexual",  { ptName: "Blob Bissexual",    en: "Bisexual pride blob.",  pt: "Blob da bandeira bissexual.", tags: ["blob","pride","love"] });
set("EmoticonData_BlobBlushing",  { ptName: "Blob Corado",       en: "Blushing blob.",        pt: "Blob corado.",             tags: ["blob","cute","love"] });
set("EmoticonData_BlobboCheer",   { ptName: "Blobbo Comemora",   en: "Blobbo cheering.",      pt: "Festa do Blobbo.",         tags: ["blob","celebration","happy","cute"] });
set("EmoticonData_BlobboLove",    { ptName: "Blobbo Amor",       en: "Blobbo love.",          pt: "Blobbo apaixonado.",       tags: ["blob","love","cute"] });
set("EmoticonData_BlobboParty",   { ptName: "Festa do Blobbo",   en: "Blobbo party.",         pt: "Blobbos na festa.",        tags: ["blob","celebration","happy"] });
set("EmoticonData_BlobboPile",    { ptName: "Pilha de Blobbo",   en: "Blobbo pile.",          pt: "Pilha de blobbos.",        tags: ["blob","cute","funny"] });
set("EmoticonData_BlobConfused",  { ptName: "Blob Confuso",      en: "Confused blob.",        pt: "Blob confuso.",            tags: ["blob","thinking","funny"] });
set("EmoticonData_BlobGay",       { ptName: "Blob Gay",          en: "Gay pride blob.",       pt: "Blob da bandeira gay.",    tags: ["blob","pride","love"] });
set("EmoticonData_BlobHappy",     { ptName: "Blob Feliz",        en: "Happy blob.",           pt: "Blob feliz.",              tags: ["blob","happy","cute"] });
set("EmoticonData_BlobLesbian",   { ptName: "Blob Lésbica",      en: "Lesbian pride blob.",   pt: "Blob da bandeira lésbica.", tags: ["blob","pride","love"] });
set("EmoticonData_BlobMad",       { ptName: "Blob Bravo",        en: "Mad blob.",             pt: "Blob bravo.",              tags: ["blob","angry","funny"] });
set("EmoticonData_BlobNonbinary", { ptName: "Blob Não-Binário",  en: "Nonbinary pride blob.", pt: "Blob da bandeira não-binária.", tags: ["blob","pride","love"] });
set("EmoticonData_BlobPansexual", { ptName: "Blob Pansexual",    en: "Pansexual pride blob.", pt: "Blob da bandeira pansexual.", tags: ["blob","pride","love"] });
set("EmoticonData_BlobPride",     { ptName: "Blob do Orgulho",   en: "Pride!",                pt: "Orgulho!",                 tags: ["blob","pride","love"] });
set("EmoticonData_BlobSad",       { ptName: "Blob Triste",       en: "Sad blob.",             pt: "Blob triste.",             tags: ["blob","sad","cute"] });
set("EmoticonData_BlobTrans",     { ptName: "Blob Trans",        en: "Trans pride blob.",     pt: "Blob da bandeira trans.",  tags: ["blob","pride","love"] });

// ── Discord / Wumpus ─────────────────────────────────────────────────────────
set("EmoticonData_T_Emoticon_WumpusFive",{ enName: "Wumpus Five", ptName: "Wumpus 5up", en: "Wumpus throwing five.", pt: "Wumpus dando 5up.", tags: ["discord","collab","cute","funny"] });
set("EmoticonData_T_Emoticon_WumpusGoalie",{ enName: "Wumpus Goalie", ptName: "Wumpus Goleiro", en: "Wumpus on goalie duty.", pt: "Wumpus no gol.", tags: ["discord","collab","cute","funny"] });
set("EmoticonData_T_Emoticon_WumpusStrike",{ enName: "Wumpus Strike", ptName: "Wumpus Atacante", en: "Wumpus striking.", pt: "Wumpus chutando.", tags: ["discord","collab","cute","funny"] });

// ── Ranks / Badges ───────────────────────────────────────────────────────────
set("EmoticonData_BPC",           { enName: "BPC", ptName: "BPC", en: "Beta-pass collector badge.", pt: "Insígnia de colecionador do passe Beta.", tags: ["rank"], review: "needs-image" });
set("EmoticonData_BPS1Badge1",    { enName: "Beta Season Striker Badge", ptName: "Insígnia Beta Striker", en: "Beta-season striker badge.", pt: "Insígnia da Beta Season.", tags: ["rank"] });
set("EmoticonData_Challenger",    { enName: "Beta Season - Challenger Icon", ptName: "Ícone Challenger Beta", en: "Beta-season Challenger badge.", pt: "Ícone Challenger da Beta Season.", tags: ["rank"] });
set("EmoticonData_Diamond",       { enName: "Beta Season - Diamond Icon", ptName: "Ícone Diamante Beta", en: "Beta-season Diamond badge.", pt: "Ícone Diamante da Beta Season.", tags: ["rank"] });
set("EmoticonData_Founder",       { enName: "Founders Pack Icon", ptName: "Ícone Founders Pack", en: "Founders pack badge.", pt: "Insígnia do Founders Pack.", tags: ["rank"] });
set("EmoticonData_Gold",          { enName: "Beta Season - Gold Icon", ptName: "Ícone Ouro Beta", en: "Beta-season Gold badge.", pt: "Ícone Ouro da Beta Season.", tags: ["rank"] });
set("EmoticonData_Omega",         { enName: "Beta Season - Omega Icon", ptName: "Ícone Omega Beta", en: "Beta-season Omega badge.", pt: "Ícone Omega da Beta Season.", tags: ["rank"] });
set("EmoticonData_Platinum",      { enName: "Beta Season - Platinum Icon", ptName: "Ícone Platina Beta", en: "Beta-season Platinum badge.", pt: "Ícone Platina da Beta Season.", tags: ["rank"] });

// ── Pro League / Esports orgs ────────────────────────────────────────────────
set("EmoticonData_ProLeague",     { ptName: "Pro League",        en: "Pro League badge.",     pt: "Insígnia da Pro League.",  tags: ["proleague"] });
set("EmoticonData_ProLeagueVS",   { ptName: "Pro League VS",     en: "Pro League VS badge.",  pt: "Insígnia da Pro League VS.", tags: ["proleague"] });
set("EmoticonData_ProLeagueVSByteBreaker",{ enName: "Byte Breakers", ptName: "Byte Breakers", en: "Go ByteBreakers!", pt: "Vai, ByteBreakers!", tags: ["proleague","lore"] });
set("EmoticonData_ProLeagueVSClarionCorp",{ enName: "Clarion Corp", ptName: "Clarion Corp", en: "Clarion Corp colors.", pt: "Cores da Clarion Corp.", tags: ["proleague","lore"] });
set("EmoticonData_ProLeagueVSDemonDrive",{ enName: "Demon Drive", ptName: "Demon Drive", en: "Go DemonDrive!", pt: "Vai, DemonDrive!", tags: ["proleague","lore"] });
set("EmoticonData_ProLeagueVSEmberMonarchs",{ enName: "Ember Monarchs", ptName: "Ember Monarchs", en: "Go EmberMonarchs!", pt: "Vai, EmberMonarchs!", tags: ["proleague","lore"] });
set("EmoticonData_ProLeagueVSFrostfire",{ enName: "Frostfire", ptName: "Frostfire", en: "Go Frostfire!", pt: "Vai, Frostfire!", tags: ["proleague","lore"] });
set("EmoticonData_ProLeagueVSMaelstrom",{ enName: "Maelstrom", ptName: "Maelstrom", en: "Go Maelstrom!", pt: "Vai, Maelstrom!", tags: ["proleague","lore"] });
set("EmoticonData_ProLeagueVSSSR",{ enName: "SSR", ptName: "SSR", en: "Go SSR!", pt: "Vai, SSR!", tags: ["proleague","lore"] });

// Real-world esports orgs (grounded)
set("EmoticonData_TeamByteBreaker",{ enName: "Team EDM", ptName: "Team EDM", en: "Repping Team ByteBreaker.", pt: "Bandeira da Team ByteBreaker.", tags: ["proleague","collab"] });
set("EmoticonData_TeamEDM",       { ptName: "Team EDM",          en: "Repping Team EDM.",     pt: "Bandeira da Team EDM.",    tags: ["proleague","collab"] });
set("EmoticonData_TeamEqwaak",    { ptName: "Team Eqwaak",       en: "Repping Team Eqwaak.",  pt: "Bandeira da Team Eqwaak.", tags: ["proleague","collab"] });
set("EmoticonData_TeamOJ",        { ptName: "Team OJ",           en: "Repping Team OJ.",      pt: "Bandeira da Team OJ.",     tags: ["proleague","collab"] });
set("EmoticonData_TeamQueso",     { ptName: "Team Queso",        en: "Repping Team Queso.",   pt: "Bandeira da Team Queso.",  tags: ["proleague","collab"] });
set("EmoticonData_TeamRock",      { ptName: "Team Rock",         en: "Repping Team Rock.",    pt: "Bandeira da Team Rock.",   tags: ["proleague","collab"] });
set("EmoticonData_TeamRPI",       { ptName: "Team RPI",          en: "Repping Team RPI.",     pt: "Bandeira da Team RPI.",    tags: ["proleague","collab"] });
set("EmoticonData_WestValleyStormStrikers",{ ptName: "West Valley Storm Strikers", en: "West Valley Storm Strikers crest.", pt: "Brasão dos West Valley Storm Strikers.", tags: ["college","collab"] });

// ── Clarion VS / Story arc ───────────────────────────────────────────────────
set("EmoticonData_ClarionVSEnergyTeam",{ enName: "Team Energy Manipulation", ptName: "Time Manipulação de Energia", en: "Energy manipulation team.", pt: "Time de manipulação de energia.", tags: ["lore","proleague"] });
set("EmoticonData_ClarionVSReward",{ enName: "Intriguing", ptName: "Intrigante", en: "Intriguing.", pt: "Intrigante.",          tags: ["lore","reaction","thinking"] });
set("EmoticonData_ClarionVSStrengthTeam",{ enName: "Team Super Strength", ptName: "Time Super Força", en: "Super strength team.", pt: "Time da super força.", tags: ["lore","proleague"] });
set("EmoticonData_ClarionVSTechTeam",{ enName: "Team Omega Tech", ptName: "Time Omega Tech", en: "Omega Tech team.", pt: "Time Omega Tech.", tags: ["lore","proleague"] });
set("EmoticonData_MusicVS_EdmOni1",{ enName: "EDM!", ptName: "EDM!", en: "EDM event.",       pt: "Evento EDM.",              tags: ["music","drekar","lore"] });
set("EmoticonData_MusicVS_RockOni",{ enName: "Rock!", ptName: "Rock!", en: "Rock event.",    pt: "Evento Rock.",             tags: ["music","drekar","lore"] });

// ── Mastery emotes (need image to confirm archetype → striker; see strikers.md TBDs)
set("EmoticonData_AngelicSupportMastery",{ enName: "Pray to The Stars", ptName: "Reza Para as Estrelas", en: "Pray to the stars.", pt: "Reza para as estrelas.", tags: ["mastery","estelle"], review: "needs-image: confirm AngelicSupport→Estelle." });
set("EmoticonData_AngelicSupportMasteryAnimated",{ enName: "Sigh...", ptName: "Suspiro...", en: "Sigh...", pt: "Suspiro...", tags: ["mastery","estelle","sad"], review: "needs-image: confirm AngelicSupport→Estelle." });
set("EmoticonData_ChaoticRocketeerMastery",{ enName: "Good Job!", ptName: "Bom Trabalho!", en: "Good job!", pt: "Bom trabalho!", tags: ["mastery","kazan","approval","happy"], review: "needs-image: confirm ChaoticRocketeer→Kazan." });
set("EmoticonData_ChaoticRocketeerMasteryAnimated",{ enName: "Calculating", ptName: "Calculando", en: "Calculating.", pt: "Calculando.", tags: ["mastery","kazan","thinking"], review: "needs-image: confirm ChaoticRocketeer→Kazan." });
set("EmoticonData_CleverSummonerMastery",{ enName: "Shocked", ptName: "Chocada", en: "Shocked.", pt: "Chocada.", tags: ["mastery","juno","shocked"], review: "needs-image: confirm CleverSummoner→Juno." });
set("EmoticonData_CleverSummonerMasteryAnimated",{ enName: "Juno Shake", ptName: "Juno Treme", en: "Juno shake.", pt: "Juno tremendo.", tags: ["mastery","juno","funny"] });
set("EmoticonData_DrumOniMastery",{ enName: "WOO", ptName: "WOO", en: "Woo!", pt: "Woo!", tags: ["mastery","drekar","music","celebration"], review: "needs-image: confirm DrumOni→Drek'ar." });
set("EmoticonData_DrumOniMasteryAnimated",{ enName: "Oni Bongo", ptName: "Oni no Bongô", en: "Oni on the bongo.", pt: "Oni no bongô.", tags: ["mastery","drekar","music","funny"], review: "needs-image: confirm DrumOni→Drek'ar." });
set("EmoticonData_EDMOniMastery", { enName: "Shrug", ptName: "Dá de Ombros", en: "Shrug.", pt: "Dá de ombros.", tags: ["mastery","drekar","music"], review: "needs-image: confirm EDMOni→Drek'ar." });
set("EmoticonData_EDMOniMasteryAnimated",{ enName: "Yawn...", ptName: "Bocejo...", en: "Yawn...", pt: "Bocejo...", tags: ["mastery","drekar","music","sleepy"], review: "needs-image: confirm EDMOni→Drek'ar." });
set("EmoticonData_EmpoweringEnchanterMastery",{ enName: "Was that...Me?!?", ptName: "Isso foi... Eu?!", en: "Was that... me?!", pt: "Isso foi... eu?!", tags: ["mastery","era","shocked"], review: "needs-image: confirm EmpoweringEnchanter→Era." });
set("EmoticonData_EmpoweringEnchanterMasteryAnimated",{ enName: "This is Fine...", ptName: "Tá Tudo Bem...", en: "This is fine.", pt: "Tá tudo bem.", tags: ["mastery","era","meme","funny"], review: "needs-image: confirm EmpoweringEnchanter→Era." });
set("EmoticonData_FlashySwordsmanMastery",{ enName: "...", ptName: "...", en: "...", pt: "...", tags: ["mastery","asher"], review: "needs-image: confirm FlashySwordsman→Asher." });
set("EmoticonData_FlashySwordsmanMasteryAnimated",{ enName: "Laughing Out Loud", ptName: "Rindo Alto", en: "Laughing out loud.", pt: "Rindo alto.", tags: ["mastery","asher","happy","funny"], review: "needs-image: confirm FlashySwordsman→Asher." });
set("EmoticonData_FlexibleBrawlerMastery",{ enName: "Success", ptName: "Sucesso", en: "Success.", pt: "Sucesso.", tags: ["mastery","juliette","celebration"], review: "needs-image: confirm FlexibleBrawler→Juliette." });
set("EmoticonData_FlexibleBrawlerMasteryAnimated",{ enName: "Firey Determination", ptName: "Determinação Ardente", en: "Firey determination.", pt: "Determinação ardente.", tags: ["mastery","juliette","fight","cool"], review: "needs-image: confirm FlexibleBrawler→Juliette." });
set("EmoticonData_GravityMageMastery",{ enName: "Reversal", ptName: "Reversão", en: "Reversal.", pt: "Reversão.", tags: ["mastery","luna","magic","cool"], review: "needs-image: confirm GravityMage→Luna." });
set("EmoticonData_GravityMageMasteryAnimated",{ enName: "Bonk", ptName: "Bonk", en: "Bonk.", pt: "Bonk.", tags: ["mastery","luna","meme","funny"], review: "needs-image: confirm GravityMage→Luna." });
set("EmoticonData_HealerMastery", { enName: "Okay", ptName: "Tá", en: "Okay.", pt: "Tá.", tags: ["mastery","nao","approval"], review: "needs-image: confirm Healer→Nao." });
set("EmoticonData_HealerMasteryAnimated",{ enName: "Mad Nao", ptName: "Nao Brava", en: "Mad Nao.", pt: "Nao brava.", tags: ["mastery","nao","angry","funny"] });
set("EmoticonData_HulkingBeastMastery",{ enName: "FleXing", ptName: "Mostrando o BíceX", en: "X flexing.", pt: "X mostrando o bíceps.", tags: ["mastery","x","cool","funny"] });
set("EmoticonData_HulkingBeastMasteryAnimated",{ enName: "I'm... X-TRA", ptName: "Eu Sou X-TRA", en: "I'm X-TRA.", pt: "Eu sou X-TRA.", tags: ["mastery","x","taunt","funny"] });
set("EmoticonData_MagicalPlaymakerMastery",{ enName: "Laser Eyes", ptName: "Olhos de Laser", en: "Laser eyes.", pt: "Olhos de laser.", tags: ["mastery","aimi","magic","cool","cat"] });
set("EmoticonData_MagicalPlaymakerMasteryAnimated",{ enName: "Keyboard Ai.Mi", ptName: "Ai.Mi no Teclado", en: "Keyboard Ai.Mi.", pt: "Ai.Mi no teclado.", tags: ["mastery","aimi","funny","cat"] });
set("EmoticonData_ManipulatingMastermindMastery",{ enName: "Evil Intensifies", ptName: "O Mal Intensifica", en: "Evil intensifies.", pt: "O mal intensifica.", tags: ["mastery","vyce","taunt","cool"], review: "needs-image: confirm ManipulatingMastermind→Vyce." });
set("EmoticonData_ManipulatingMastermindMasteryAnimated",{ enName: "NANI?!?!", ptName: "NANI?!?!", en: "Nani?!", pt: "Nani?!", tags: ["mastery","vyce","shocked","meme","funny"], review: "needs-image: confirm ManipulatingMastermind→Vyce." });
set("EmoticonData_NimbleBlasterMastery",{ enName: "Drek'ar Think", ptName: "Drek'ar Pensando", en: "Drek'ar thinking.", pt: "Drek'ar pensando.", tags: ["mastery","drekar","thinking"], review: "needs-image: 'NimbleBlaster' could be Finii — emote name says Drek'ar but archetype suggests blaster striker." });
set("EmoticonData_NimbleBlasterMasteryAnimated",{ enName: "Madge", ptName: "Madge", en: "Madge.", pt: "Madge.", tags: ["mastery","angry","meme"], review: "needs-image: which striker?" });
set("EmoticonData_RockOniMastery",{ enName: "Bleh", ptName: "Bleh", en: "Bleh.", pt: "Bleh.", tags: ["mastery","drekar","music","disapproval"], review: "needs-image: confirm RockOni→Drek'ar." });
set("EmoticonData_RockOniMasteryAnimated",{ enName: "Rock On!", ptName: "Manda Brasa!", en: "Rock on!", pt: "Manda brasa!", tags: ["mastery","drekar","music","celebration"], review: "needs-image: confirm RockOni→Drek'ar." });
set("EmoticonData_ShieldUserMastery",{ enName: "Looking Sus", ptName: "Tá Suspeito", en: "Looking sus.", pt: "Tá suspeito.", tags: ["mastery","rasmus","meme","thinking"], review: "needs-image: confirm ShieldUser→Rasmus." });
set("EmoticonData_ShieldUserMasteryAnimated",{ enName: "Yikes!", ptName: "Eita!", en: "Yikes!", pt: "Eita!", tags: ["mastery","rasmus","shocked","funny"], review: "needs-image: confirm ShieldUser→Rasmus." });
set("EmoticonData_SpeedySkirmisherMastery",{ enName: "Play Better?", ptName: "Joga Melhor?", en: "Play better?", pt: "Joga melhor?", tags: ["mastery","taunt","funny"], review: "needs-image: which striker is SpeedySkirmisher?" });
set("EmoticonData_SpeedySkirmisherMasteryAnimated",{ enName: "Burn It Down!", ptName: "Queima Tudo!", en: "Burn it down.", pt: "Queima tudo.", tags: ["mastery","fight","cool"], review: "needs-image: which striker is SpeedySkirmisher?" });
set("EmoticonData_StalwartProtectorMastery",{ enName: "OmegaLul Dubu", ptName: "OmegaLul Dubu", en: "OmegaLul Dubu.", pt: "OmegaLul Dubu.", tags: ["mastery","dubu","funny","meme"] });
set("EmoticonData_StalwartProtectorMasteryAnimated",{ enName: "LET'S GOOO!", ptName: "VAMO!", en: "Let's gooo!", pt: "Vamo!", tags: ["mastery","dubu","celebration","happy"] });
set("EmoticonData_TempoSniperMastery",{ enName: "Smell The Roses", ptName: "Sente o Cheiro das Rosas", en: "Smell the roses.", pt: "Sente o cheiro das rosas.", tags: ["mastery","mako","cool"], review: "needs-image: confirm TempoSniper→Mako." });
set("EmoticonData_TempoSniperMasteryAnimated",{ enName: "Here's A Kiss", ptName: "Toma um Beijinho", en: "Here's a kiss.", pt: "Toma um beijinho.", tags: ["mastery","mako","love","cute"], review: "needs-image: confirm TempoSniper→Mako." });
set("EmoticonData_UmbrellaUserMastery",{ enName: "Losin' It", ptName: "Perdendo a Cabeça", en: "Losin' it.", pt: "Perdendo a cabeça.", tags: ["mastery","angry","funny"], review: "needs-image: which striker is UmbrellaUser?" });
set("EmoticonData_UmbrellaUserMasteryAnimated",{ enName: "Raining", ptName: "Chovendo", en: "Raining.", pt: "Chovendo.", tags: ["mastery","sad"], review: "needs-image: which striker is UmbrellaUser?" });
set("EmoticonData_WhipFighterMastery",{ enName: "Try That Again", ptName: "Tenta de Novo", en: "Try that again.", pt: "Tenta de novo.", tags: ["mastery","taunt","cool"], review: "needs-image: which striker is WhipFighter? Archetype 'whip' may not be a literal whip in the visual." });
set("EmoticonData_WhipFighterMasteryAnimated",{ enName: "SHOCKINGLY TERRIBLE", ptName: "CHOCANTEMENTE TERRÍVEL", en: "Shockingly terrible.", pt: "Chocantemente terrível.", tags: ["mastery","taunt","cool"], review: "needs-image: which striker is WhipFighter?" });

// ── Misc OS-bubble / lore / community ────────────────────────────────────────
set("EmoticonData_DefaultThumbsUp",{ enName: "Thumbs Up", ptName: "Joinha", en: "Thumbs up.", pt: "Joinha.", tags: ["reaction","approval","happy"] });
set("EmoticonData_GooseMorning",  { ptName: "Good Goose Morning", en: "Goose morning.", pt: "Good goose morning.", tags: ["community","meme","funny"] });
set("EmoticonData_WaterlooGooseWrangler",{ ptName: "Domador de Gansos de Waterloo", en: "Waterloo Goose Wrangler.", pt: "Domador de gansos de Waterloo.", tags: ["college","community","meme","funny"] });
set("EmoticonData_StrikerCentral",{ ptName: "Striker Central",   en: "Striker Central tribute.", pt: "Homenagem ao Striker Central.", tags: ["community","collab"] });
set("EmoticonData_UNStrikers",    { ptName: "UNStrikers",        en: "UNStrikers tribute.",   pt: "Homenagem ao UNStrikers.", tags: ["community","collab"] });
set("EmoticonData_IKeepItTaco",   { enName: "I Keep It Taco", ptName: "Eu Mantenho o Taco", en: "Keep it taco.", pt: "Bora de taco.", tags: ["community","meme","food","funny"] });
set("EmoticonData_BeatEmUps",     { enName: "Beat Em Ups", ptName: "Beat Em Ups", en: "Beat Em Ups tribute.", pt: "Homenagem ao Beat Em Ups.", tags: ["streamer","community","collab"] });
set("EmoticonData_BestieInSlot",  { enName: "Bestie In Slot", ptName: "Bestie In Slot", en: "Bestie in slot.", pt: "Bestie in slot.", tags: ["meme","community","funny"], review: "needs-image" });
set("EmoticonData_CoreBoyHello",  { enName: "Core Boy THX", ptName: "Core Boy Valeu", en: "Core Boy says thanks.", pt: "Core Boy agradecendo.", tags: ["community","greeting","cute"], review: "needs-image" });
set("EmoticonData_SADBOIS",       { ptName: "SADBOIS",           en: "SADBOIS crew.",         pt: "Crew SADBOIS.",            tags: ["community","collab","sad"], review: "needs-image" });
set("EmoticonData_CaptainShota",  { ptName: "Capitão Shota",     en: "Captain Shota.",        pt: "Capitão Shota.",           tags: ["community","collab"], review: "needs-image: is this a striker skin or community emote?" });
set("EmoticonData_WiwiSmile",     { ptName: "Sorriso da Wiwi",   en: "Wiwi smile.",           pt: "Sorriso da Wiwi.",         tags: ["community"], review: "needs-image: identify Wiwi (skin? streamer?)" });
set("EmoticonData_Cloudburst",    { ptName: "Cloudburst",        en: "Cloudburst.",           pt: "Cloudburst.",              tags: ["lore"], review: "needs-image" });

// ── Streamers (grounded tributes; pre-listed Western/global names below; rest get tribute via rules) ──
// Confident-streamer overrides — kept for parallel structure / clarity
set("EmoticonData_5up",           { ptName: "5up",               en: "5up tribute.",          pt: "Homenagem ao 5up.",        tags: ["streamer","collab"] });
set("EmoticonData_xQc",           { enName: "xQc", ptName: "xQc", en: "xQc tribute.",         pt: "Homenagem ao xQc.",        tags: ["streamer","collab","meme"] });
set("EmoticonData_Ludwig",        { ptName: "Ludwig",            en: "Ludwig tribute.",       pt: "Homenagem ao Ludwig.",     tags: ["streamer","collab"] });
set("EmoticonData_Valkyrae",      { ptName: "Valkyrae",          en: "Valkyrae tribute.",     pt: "Homenagem à Valkyrae.",    tags: ["streamer","collab"] });
set("EmoticonData_Cellbit",       { ptName: "Cellbit",           en: "Cellbit tribute.",      pt: "Homenagem ao Cellbit.",    tags: ["streamer","collab"] });
set("EmoticonData_TimTheTatman",  { enName: "TimTheTatman", ptName: "TimTheTatman", en: "TimTheTatman tribute.", pt: "Homenagem ao TimTheTatman.", tags: ["streamer","collab"] });
set("EmoticonData_AsmonGold",     { enName: "Asmongold", ptName: "Asmongold", en: "Asmongold tribute.", pt: "Homenagem ao Asmongold.", tags: ["streamer","collab"] });

// Sonii (community personality) — multiple emotes
set("EmoticonData_SoniiPepega",   { ptName: "Sonii Pepega",      en: "Sonii Pepega.",         pt: "Sonii Pepega.",            tags: ["streamer","community","collab","meme"] });
set("EmoticonData_SoniiSalute",   { ptName: "Continência do Sonii", en: "Sonii salute.",       pt: "Continência do Sonii.",   tags: ["streamer","community","collab","greeting"] });
set("EmoticonData_SoniiTank",     { ptName: "Sonii",             en: "Sonii portrait.",       pt: "Retrato do Sonii.",        tags: ["streamer","community","collab"] });
set("EmoticonData_SoniiTrophy",   { enName: "Sonii W", ptName: "W do Sonii", en: "Sonii W.",   pt: "W do Sonii.",              tags: ["streamer","community","collab","celebration"] });
set("EmoticonData_SoniiWires",    { ptName: "Sonii Fios",        en: "Sonii wires.",          pt: "Sonii enrolado nos fios.", tags: ["streamer","community","collab","funny"] });
set("EmoticonData_SoniiWTank",    { ptName: "Sonii W",           en: "Sonii W tank.",         pt: "Sonii W.",                 tags: ["streamer","community","collab","celebration"] });

// ── Lore characters / Onigiri / Drek'ar tournament arc ───────────────────────
set("EmoticonData_Onigiri",       { ptName: "Onigiri",           en: "Onigiri.",              pt: "Onigiri.",                 tags: ["food","lore"], review: "needs-image: lore character or rice ball?" });
set("EmoticonData_Aethelstan",    { ptName: "Aethelstan",        en: "Aethelstan.",           pt: "Aethelstan.",              tags: ["lore"], review: "needs-image" });
set("EmoticonData_OniRelease",    { enName: "Menace", ptName: "Ameaça", en: "Oni unleashed.", pt: "Oni solto.",               tags: ["drekar","lore","angry","cool"], review: "needs-image: confirm Drek'ar." });
set("EmoticonData_Uthenera",      { ptName: "Uthenera",          en: "Uthenera.",             pt: "Uthenera.",                tags: ["lore"], review: "needs-image" });

// ──────────────────────────────────────────────────────────────────────────────
// Rules: classify and produce defaults for entries WITHOUT an override.
// ──────────────────────────────────────────────────────────────────────────────

// Streamer/personality single-name fallback set.
// These all become "tribute emote" with [streamer, collab] tags.
const STREAMER_FALLBACK = new Set([
    "Alpharad","Ariken","AustinFelt","Blau","Blau2","Blau3","CDawg","Code","Colin","Courage",
    "DrLupo","Ducky","Dyrus","Egoraptor","Enviosity","Fumi","FumikoHoshi","Fuslie","GameGrumps",
    "Guchitsubo","Hafu","Hanjou","HyperX","IceStream","Japanalysis","Jrokez","K4sen","KinbutaKyo",
    "Lily","Lirik","LJoga","Mang0","Mely","Meteos","Moist","MyMrFruit","Necrit","Nemu","Nyanners",
    "Obo","OoenoTakayuki","Radda","Rakin","Rayditz","Rejekun","RomainLive","Ross","SanninShow",
    "Scarra","Shaka","SKJVillage","Sneaky","Sonho","Sp4zie","SPYGEA","Sumomo","Sykkuno","Taiji",
    "Techzz","Tori","Tuonto","Vernias","Vienna","VigilRec","Yakkocmm","Yoda","zEmerson",
    "ZentreyaSalt","Zeroljuin","ZenTank","TH"
]);

const STREAMER_RENAME = {
    "EmoticonData_Sp4zie":      "Sp4zie",
    "EmoticonData_zEmerson":    "zEmerson",
    "EmoticonData_K4sen":       "K4sen",
    "EmoticonData_AsmonGold":   "Asmongold",
    "EmoticonData_ZentreyaSalt":"Zentreya Salt",
    "EmoticonData_MyMrFruit":   "MyMrFruit",
    "EmoticonData_TimTheTatman":"TimTheTatman",
    "EmoticonData_OoenoTakayuki":"Ooeno Takayuki",
};

function isPlaceholder(id) {
    return /^EmoticonData_Placeholder\d+$/.test(id) || /^EmoticonData_SchoolPlaceholder\d+$/.test(id);
}

function isExpansionSlot(id) {
    return /^EmoticonData_ExpansionSlot\d+$/.test(id);
}

function isAllCapsCollege(id, en) {
    const stem = id.replace(/^EmoticonData_/, "");
    return /^[A-Z]{4,}$/.test(stem) && stem === en;
}

function isCollegeLong(id) {
    const stem = id.replace(/^EmoticonData_/, "");
    return /(Esports|Gaming|University|College|Strikers|esports|Warriors)/i.test(stem) && !/Striker(Affinity|Central)/.test(stem) && stem !== "UNStrikers" && stem !== "WestValleyStormStrikers";
}

function streamerStem(id) {
    const stem = id.replace(/^EmoticonData_/, "");
    return STREAMER_FALLBACK.has(stem) ? stem : null;
}

function isStreamerExpansion(en) {
    // ExpansionSlot1..N have names like "Heh Finii - SpaceZino5" (community-made).
    // Match any non-whitespace after " - " so non-Latin creator names (e.g. "エグゾテックOTP") still count.
    return /-\s+\S/.test(en) && !/^Expansion Slot \d+$/.test(en);
}

function cleanDisplayName(en) {
    // Fix common parsing artifacts: "x Qc" → "xQc", "Sp 4zie" → "Sp4zie", "z Emerson" → "zEmerson",
    // "u Ottawa Esports" → "uOttawa Esports", "Ai Mi X" → "Ai.Mi X", "OCEAi Mi" → "OCEAi.Mi"
    if (!en) return en;
    return en
        .replace(/^x Qc$/, "xQc")
        .replace(/^Sp 4zie$/, "Sp4zie")
        .replace(/^z Emerson$/, "zEmerson")
        .replace(/^u Ottawa Esports$/, "uOttawa Esports")
        .replace(/^Ai Mi /, "Ai.Mi ")
        .replace(/^Asmon Gold$/, "Asmongold")
        .replace(/^K 4sen$/, "K4sen")
        .replace(/^OCEAi Mi$/, "OCEAi.Mi");
}

// ──────────────────────────────────────────────────────────────────────────────
// Build entries
// ──────────────────────────────────────────────────────────────────────────────

function buildEntry(pair) {
    const id = pair.id;
    const enExisting = cleanDisplayName(pair.en);

    const ov = O[id];
    if (ov) {
        const entry = {
            id,
            source: "native",
            name: { en: ov.enName || enExisting, "pt-BR": ov.ptName },
            description: { en: ov.en, "pt-BR": ov.pt },
            tags: ov.tags,
            visual_asset_path: "",
        };
        if (ov.review) entry._review = ov.review;
        return entry;
    }

    // No override → classify and apply rule
    const stem = id.replace(/^EmoticonData_/, "");

    if (isPlaceholder(id)) {
        return {
            id, source: "native",
            name: { en: enExisting, "pt-BR": enExisting.replace(/Placeholder/i, "Reservado").replace(/School/i, "Universidade") },
            description: { en: "Reserved slot.", "pt-BR": "Slot reservado." },
            tags: ["placeholder"],
            visual_asset_path: "",
        };
    }

    if (isExpansionSlot(id)) {
        const isCreator = isStreamerExpansion(enExisting);
        return {
            id, source: "native",
            name: { en: enExisting, "pt-BR": enExisting },
            description: {
                en: isCreator ? "Community-made expansion emote." : "Reserved expansion slot.",
                "pt-BR": isCreator ? "Emote feito pela comunidade." : "Slot de expansão reservado.",
            },
            tags: isCreator ? ["community","collab","placeholder"] : ["placeholder"],
            visual_asset_path: "",
            _review: isCreator ? "needs-image: identify striker depicted (creator credit in en name)." : undefined,
        };
    }

    if (isAllCapsCollege(id, pair.en)) {
        return {
            id, source: "native",
            name: { en: enExisting, "pt-BR": enExisting },
            description: { en: `${enExisting} esports crest.`, "pt-BR": `Brasão do esports da ${enExisting}.` },
            tags: ["college","collab"],
            visual_asset_path: "",
        };
    }

    if (isCollegeLong(id)) {
        return {
            id, source: "native",
            name: { en: enExisting, "pt-BR": enExisting },
            description: { en: `${enExisting} crest.`, "pt-BR": `Brasão do ${enExisting}.` },
            tags: ["college","collab"],
            visual_asset_path: "",
        };
    }

    if (streamerStem(id)) {
        const display = STREAMER_RENAME[id] || enExisting;
        return {
            id, source: "native",
            name: { en: display, "pt-BR": display },
            description: { en: `${display} tribute.`, "pt-BR": `Homenagem ao ${display}.` },
            tags: ["streamer","collab"],
            visual_asset_path: "",
        };
    }

    // Catch-all: short ambiguous IDs (CCL, CMU, NASL, OSE, ESUG, IEN, IHSEA, KING, RSU, SCAD, SEMO, TAMU, TMU, UAB, UBC, UCSB, UHSP, USM, etc.) → treat as college acronyms
    if (/^[A-Z0-9_]{2,12}$/.test(stem) && stem === enExisting) {
        return {
            id, source: "native",
            name: { en: enExisting, "pt-BR": enExisting },
            description: { en: `${enExisting} esports crest.`, "pt-BR": `Brasão do ${enExisting} esports.` },
            tags: ["college","collab"],
            visual_asset_path: "",
        };
    }

    // Last resort: unknown ambiguous entry
    return {
        id, source: "native",
        name: { en: enExisting, "pt-BR": enExisting },
        description: { en: `${enExisting}.`, "pt-BR": `${enExisting}.` },
        tags: [],
        visual_asset_path: "",
        _review: "needs-image: uncategorized — confirm what this depicts.",
    };
}

const emotes = pairs.map(buildEntry);

// ──────────────────────────────────────────────────────────────────────────────
// Emit catalog.json
// ──────────────────────────────────────────────────────────────────────────────
const tagsOut = {};
for (const [key, val] of Object.entries(TAGS)) {
    tagsOut[key] = { label: { en: val.en, "pt-BR": val.pt } };
}

const out = {
    schema_version: 1,
    default_locale: "en",
    tags: tagsOut,
    emotes,
};

fs.writeFileSync(OUT, JSON.stringify(out, null, 2) + "\n", "utf8");

// ──────────────────────────────────────────────────────────────────────────────
// Stats
// ──────────────────────────────────────────────────────────────────────────────
const stats = {
    total: emotes.length,
    overridden: emotes.filter(e => O[e.id]).length,
    needsReview: emotes.filter(e => e._review).length,
    byCategory: {
        striker: emotes.filter(e => e.tags.some(t => ["asher","aimi","atlas","drekar","dubu","era","estelle","finii","juliette","juno","kai","kazan","luna","mako","nao","octavia","rasmus","rune","vyce","x","zentaro"].includes(t))).length,
        college: emotes.filter(e => e.tags.includes("college")).length,
        streamer: emotes.filter(e => e.tags.includes("streamer")).length,
        mastery: emotes.filter(e => e.tags.includes("mastery")).length,
        skin: emotes.filter(e => e.tags.includes("skin")).length,
        blob: emotes.filter(e => e.tags.includes("blob")).length,
        tactic: emotes.filter(e => e.tags.includes("tactic")).length,
        rank: emotes.filter(e => e.tags.includes("rank")).length,
        placeholder: emotes.filter(e => e.tags.includes("placeholder")).length,
        proleague: emotes.filter(e => e.tags.includes("proleague")).length,
        discord: emotes.filter(e => e.tags.includes("discord")).length,
        untagged: emotes.filter(e => e.tags.length === 0).length,
    },
};

console.log("Stats:", JSON.stringify(stats, null, 2));
console.log("Wrote", OUT);
