// افزودنِ لغاتِ سطحِ C2 به paid-content/vocab_in_use_words.json — idempotent: node scripts/add-vocab-c2.mjs
// فرمتِ هر خط:  en|دسته|example|collocation     (دسته = کلیدِ کوتاهِ ALIAS پایین، که به «category» ریزِ فایل نگاشت می‌شود)
// فقط انگلیسی (fa خالی می‌ماند؛ ترجمه را سیستمِ ترجمه‌ی اپ انجام می‌دهد).
// لغتِ تکراری (در هر سه لیستِ slang / daily / vocab) اضافه نمی‌شود. شناسه‌ها از ۸۰۰۰۰۰ شروع می‌شوند
// (≥ ۵۰۰۰۰۰ ⇒ طبقِ build-paid-content هرگز رایگان نمی‌شود).
// بعد از اجرا: node scripts/build-paid-content.mjs --assets && node scripts/build-paid-content.mjs --sql content_seed
import fs from "node:fs";

const ALIAS = {
  adj: "صفت‌ها", adv: "قیدها", coll: "هم‌نشین‌های واژگانی (کالوکیشن)", pv: "افعال عبارتی ۲: دستور و سبک",
  fix: "عبارات ثابت", multi: "عبارات چندکلمه‌ای", formal: "انگلیسی رسمی و غیررسمی", essay: "نوشتن مقاله/انشا",
  link: "کلمات و عبارات ربط در گفتار", abs: "اسم‌های انتزاعی", char: "توصیف شخصیت", feel: "احساسات",
  biz: "کسب و کار", fin: "کسب و کار و امور مالی", career: "پیشرفت شغلی", pol: "سیاست", crime: "جرم و جنایت",
  sci: "علوم و فناوری", art: "هنر و ادبیات", glob: "مشکلات جهانی", env: "مشکلات زیست‌محیطی", med: "سلامت و پزشکی",
  praise: "تعریف و انتقاد", opin: "نظر، موافقت و مخالفت", succ: "موفقیت، شکست و دشواری", media: "رسانه‌ها و مطبوعات",
  edu: "آموزش عالی (دانشگاه)", simile: "تشبیه‌ها", contrast: "تضاد و مقایسه", cause: "علت، دلیل، هدف و نتیجه",
};

const C2 = `
inscrutable|adj|His inscrutable expression gave nothing away during the negotiations.|inscrutable expression
mercurial|adj|The director's mercurial temperament made long-term planning almost impossible.|mercurial temperament
intransigent|adj|Both sides remained intransigent, and the talks collapsed.|intransigent attitude
equivocal|adj|The minister gave an equivocal answer that satisfied no one.|equivocal response
disingenuous|adj|It is disingenuous to claim you were unaware of the risks.|disingenuous claim
magnanimous|adj|She was magnanimous in victory and praised her opponent's effort.|magnanimous gesture
recondite|adj|The lecture drifted into recondite points of medieval law.|recondite knowledge
perfunctory|adj|He gave the report a perfunctory glance before signing it.|perfunctory check
exacting|adj|Her exacting standards pushed the whole team to improve.|exacting standards
impervious|adj|The CEO seemed impervious to criticism from the board.|impervious to criticism
indefatigable|adj|An indefatigable campaigner, he visited every village in the region.|indefatigable energy
inexorable|adj|The inexorable rise of automation is reshaping the labour market.|inexorable decline
insidious|adj|Burnout is insidious: it creeps up on you before you notice.|insidious effect
intractable|adj|The conflict has proved intractable despite decades of diplomacy.|intractable problem
labyrinthine|adj|Applicants must navigate a labyrinthine bureaucracy to obtain a permit.|labyrinthine system
lugubrious|adj|He delivered the news in a lugubrious tone.|lugubrious expression
nebulous|adj|The proposal was too nebulous to attract any investors.|nebulous concept
ostentatious|adj|The ostentatious display of wealth embarrassed even his supporters.|ostentatious display
parsimonious|adj|The council was parsimonious with funding for the arts.|parsimonious with
pugnacious|adj|The pugnacious young lawyer relished every courtroom fight.|pugnacious attitude
quixotic|adj|Their quixotic attempt to rebuild the old factory ended in bankruptcy.|quixotic quest
sardonic|adj|He answered with a sardonic smile and a raised eyebrow.|sardonic humour
specious|adj|The argument sounds plausible but is ultimately specious.|specious reasoning
sanctimonious|adj|I can't stand his sanctimonious lectures about honesty.|sanctimonious tone
trenchant|adj|The critic's trenchant analysis exposed every weakness in the plot.|trenchant criticism
truculent|adj|The truculent customer refused to leave until he was refunded.|truculent mood
unassailable|adj|After the merger, the firm held an unassailable position in the market.|unassailable lead
vacuous|adj|The speech was full of vacuous promises and empty slogans.|vacuous remark
venerable|adj|The venerable institution has educated leaders for four centuries.|venerable tradition
voluble|adj|The voluble host kept the dinner guests entertained for hours.|voluble speaker
wanton|adj|The report condemned the wanton destruction of the ancient forest.|wanton cruelty
anodyne|adj|The press release was deliberately anodyne and avoided all controversy.|anodyne statement
byzantine|adj|The tax code has become so byzantine that few people understand it.|byzantine complexity
cavalier|adj|His cavalier attitude to safety rules cost the company dearly.|cavalier attitude
censorious|adj|The committee was censorious of any deviation from tradition.|censorious critic
churlish|adj|It would be churlish to refuse such a generous offer.|churlish to refuse
craven|adj|The senator's craven silence disappointed his own voters.|craven surrender
fractious|adj|The fractious coalition struggled to pass a single bill.|fractious relationship
frugal|adj|Raised in poverty, she remained frugal even when she became wealthy.|frugal lifestyle
gregarious|adj|A gregarious man, he knew everyone at the conference by the second day.|gregarious personality
hapless|adj|The hapless intern deleted the entire client database.|hapless victim
iconoclastic|adj|Her iconoclastic approach challenged every convention in the field.|iconoclastic approach
impecunious|adj|The impecunious poet lived in a cold attic for years.|impecunious student
inchoate|adj|At that stage the plan was still inchoate and needed refining.|inchoate idea
incisive|adj|Her incisive questions revealed the flaw in the budget.|incisive analysis
insouciant|adj|He strolled into the meeting with an insouciant grin.|insouciant manner
jejune|adj|The reviewer dismissed the novel as jejune and derivative.|jejune argument
laconic|adj|His laconic reply, just one word, said everything.|laconic reply
limpid|adj|Her limpid prose makes complex ideas easy to follow.|limpid style
mawkish|adj|The film's mawkish ending left the audience cold.|mawkish sentimentality
obdurate|adj|The landlord remained obdurate despite repeated appeals.|obdurate refusal
obstreperous|adj|The obstreperous crowd had to be escorted out of the hall.|obstreperous behaviour
opaque|adj|The company's accounting practices were deliberately opaque.|opaque language
palpable|adj|There was a palpable sense of relief when the results were announced.|palpable tension
peremptory|adj|She issued a peremptory order and left the room.|peremptory tone
precarious|adj|The firm's finances remained in a precarious state.|precarious position
prescient|adj|His prescient warning about the housing bubble was ignored.|prescient warning
profligate|adj|The government was criticised for its profligate spending.|profligate spending
prolix|adj|The contract was so prolix that nobody read it to the end.|prolix writing
pusillanimous|adj|Critics called the decision to withdraw pusillanimous.|pusillanimous leader
sagacious|adj|A sagacious investor, she sold just before the crash.|sagacious advice
salient|adj|Let me summarise the salient points of the proposal.|salient feature
scrupulous|adj|The auditor was scrupulous in checking every figure.|scrupulous attention to detail
sedulous|adj|Years of sedulous practice finally paid off.|sedulous effort
sporadic|adj|Sporadic fighting continued despite the ceasefire.|sporadic outbreak
stoic|adj|She remained stoic as the verdict was read.|stoic acceptance
sullen|adj|He gave a sullen shrug and refused to explain.|sullen silence
supercilious|adj|The waiter's supercilious smile made her feel unwelcome.|supercilious air
tenuous|adj|The link between the two events is tenuous at best.|tenuous connection
tendentious|adj|The documentary was criticised as tendentious and one-sided.|tendentious argument
unequivocal|adj|The court gave an unequivocal ruling in her favour.|unequivocal support
urbane|adj|The urbane ambassador charmed everyone at the reception.|urbane manner
vitriolic|adj|The article launched a vitriolic attack on the mayor.|vitriolic attack
wistful|adj|She gave a wistful smile at the old photographs.|wistful look
abstemious|adj|He was abstemious by habit, rarely drinking or overeating.|abstemious lifestyle
ineffable|adj|The view from the summit filled him with ineffable joy.|ineffable beauty
inimical|adj|Such policies are inimical to economic growth.|inimical to
bucolic|adj|They retired to a bucolic village far from the city.|bucolic scene
ubiquitous|adj|Smartphones have become ubiquitous in every age group.|ubiquitous presence
sedentary|adj|A sedentary lifestyle increases the risk of heart disease.|sedentary lifestyle
vicarious|adj|He lived a vicarious thrill through his daughter's success.|vicarious pleasure
tacit|adj|There was a tacit agreement not to mention the incident.|tacit approval
nascent|adj|The nascent industry needs government support to survive.|nascent industry
mendacious|adj|The candidate was exposed as mendacious after the debate.|mendacious statement
ambivalent|adj|Many voters remain ambivalent about the proposed reforms.|ambivalent about
ostensibly|adv|Ostensibly a routine visit, the trip was in fact a secret negotiation.|ostensibly for
inexplicably|adv|Inexplicably, the system crashed just before the deadline.|inexplicably absent
perfunctorily|adv|He nodded perfunctorily and returned to his screen.|nod perfunctorily
tacitly|adv|The board tacitly endorsed the plan by saying nothing.|tacitly agree
irrevocably|adv|The merger irrevocably changed the character of the firm.|irrevocably damaged
inextricably|adv|Her career is inextricably linked to the fate of the company.|inextricably linked
unabashedly|adv|He unabashedly promoted his own book at every opportunity.|unabashedly proud
tentatively|adv|The two sides have tentatively agreed to meet next month.|tentatively agree
sedulously|adv|She sedulously avoided any mention of the scandal.|sedulously avoid
incontrovertibly|adv|The data incontrovertibly show a decline in biodiversity.|incontrovertibly proven
invariably|adv|The meetings invariably overran, whatever the agenda.|almost invariably
scathingly|adv|The reviewer wrote scathingly about the director's latest film.|scathingly critical
cursorily|adv|The inspector examined the documents only cursorily.|examine cursorily
indelibly|adv|The experience left its mark indelibly on her character.|indelibly etched
unwittingly|adv|He had unwittingly revealed the secret to a journalist.|unwittingly reveal
sedately|adv|The procession moved sedately through the square.|walk sedately
cogently|adv|She argued cogently that the policy would backfire.|argue cogently
hitherto|adv|The study revealed a hitherto unknown species of frog.|hitherto unknown
inordinately|adv|The project took an inordinately long time to complete.|inordinately proud
abrogate|pv|The new government moved to abrogate the treaty.|abrogate a treaty
adjudicate|formal|An independent panel will adjudicate the dispute.|adjudicate a dispute
aggrandise|formal|He used the position to aggrandise himself at the public's expense.|self-aggrandising
alleviate|formal|The new measures should alleviate pressure on hospitals.|alleviate poverty
appease|formal|The leader made concessions in a vain attempt to appease his critics.|appease critics
arbitrate|formal|A neutral party was brought in to arbitrate between the unions and management.|arbitrate a dispute
attenuate|formal|Training can attenuate the effects of stress on performance.|attenuate the impact
bolster|formal|The announcement bolstered confidence in the economy.|bolster confidence
castigate|formal|The press castigated the minister for his handling of the crisis.|castigate someone for
circumvent|formal|Some firms use offshore accounts to circumvent the regulations.|circumvent the rules
concede|formal|The candidate was forced to concede defeat after the recount.|concede defeat
condone|formal|We cannot condone violence under any circumstances.|condone behaviour
confound|formal|The results confounded the experts' predictions.|confound expectations
conflate|formal|It is a mistake to conflate correlation with causation.|conflate A with B
countenance|formal|The school will not countenance bullying of any kind.|countenance the idea
curtail|formal|Budget cuts forced the hospital to curtail its services.|curtail spending
decry|formal|Environmental groups decried the decision to approve the mine.|publicly decry
defer|formal|I will defer to your greater experience on this matter.|defer to someone
delineate|formal|The contract clearly delineates each party's responsibilities.|delineate boundaries
deplete|formal|Overfishing has depleted fish stocks across the region.|deplete resources
deter|formal|Heavy fines may deter companies from polluting rivers.|deter crime
discern|formal|It was hard to discern any pattern in the data.|discern a trend
dispel|formal|The CEO tried to dispel rumours of an impending takeover.|dispel doubts
divulge|formal|She refused to divulge the name of her source.|divulge information
eschew|formal|The company eschews traditional advertising in favour of word of mouth.|eschew violence
exacerbate|formal|Austerity measures only exacerbated the crisis.|exacerbate the problem
exonerate|crime|New DNA evidence exonerated the man after twenty years in prison.|exonerate someone of
expedite|formal|Extra staff were hired to expedite the visa process.|expedite a process
extol|formal|Critics extolled the virtues of the new museum.|extol the virtues of
extrapolate|sci|We cannot extrapolate national trends from such a small sample.|extrapolate from data
fathom|formal|I cannot fathom why she resigned so suddenly.|fail to fathom
foment|pol|Agitators sought to foment unrest among the workers.|foment rebellion
forestall|formal|The bank acted quickly to forestall a run on deposits.|forestall criticism
gainsay|formal|No one can gainsay the importance of her contribution.|cannot be gainsaid
galvanise|formal|The disaster galvanised the public into action.|galvanise support
harbinger|abs|The sharp fall in orders was a harbinger of a wider downturn.|a harbinger of
hamper|formal|Heavy rain hampered rescue efforts.|hamper progress
impugn|formal|He resented anyone who impugned his motives.|impugn someone's integrity
inculcate|edu|Schools should inculcate a love of reading in children.|inculcate values
inhibit|formal|High interest rates inhibit investment.|inhibit growth
instigate|formal|The police instigated an inquiry into the leak.|instigate a review
lambast|praise|Commentators lambasted the government's response to the floods.|lambast someone for
mitigate|env|Planting trees can help mitigate the effects of climate change.|mitigate the effects of
mollify|formal|The manager tried to mollify the angry customer with a refund.|mollify critics
obviate|formal|Better planning would obviate the need for costly repairs.|obviate the need for
ostracise|formal|Whistleblowers are often ostracised by their colleagues.|be ostracised by
pacify|formal|Police used tear gas in an attempt to pacify the crowd.|pacify protesters
placate|formal|The airline offered vouchers to placate delayed passengers.|placate critics
preclude|formal|His injury precludes any chance of competing this season.|preclude the possibility of
proscribe|crime|The law proscribes the sale of such substances.|proscribed by law
rebuff|formal|She rebuffed every attempt to change her mind.|rebuff an offer
rectify|formal|The firm promised to rectify the error at its own expense.|rectify a mistake
relinquish|formal|The founder reluctantly relinquished control of the company.|relinquish control
repudiate|formal|The party leader repudiated the extremist views of some members.|repudiate a claim
rescind|formal|The council voted to rescind the controversial ban.|rescind a decision
stifle|formal|Excessive red tape can stifle innovation.|stifle creativity
subvert|pol|The group aimed to subvert the authority of the state.|subvert democracy
supersede|formal|The new regulations supersede all previous guidance.|supersede an earlier law
suppress|formal|The regime suppressed all forms of dissent.|suppress evidence
thwart|formal|Border guards thwarted an attempt to smuggle the artefacts out.|thwart a plan
transcend|formal|Great music can transcend language and culture.|transcend boundaries
undermine|formal|Constant leaks undermined trust within the team.|undermine confidence
usurp|pol|The general tried to usurp the throne.|usurp power
vindicate|formal|The inquiry's findings vindicated her decision to resign.|feel vindicated
waive|formal|The university agreed to waive the application fee.|waive a right
wane|formal|Public interest in the scheme began to wane.|on the wane
whittle down|pv|The committee whittled the list down to three candidates.|whittle down a list
winnow out|pv|The first round winnowed out the weaker proposals.|winnow out the weak
brush up on|pv|I need to brush up on my negotiation skills before the trip.|brush up on skills
buckle down|pv|You'll have to buckle down if you want to pass the exam.|buckle down to work
chime in|pv|She chimed in with a useful suggestion halfway through the meeting.|chime in with
clamp down on|pv|The authorities are clamping down on tax evasion.|clamp down on crime
dwell on|pv|There is no point dwelling on past mistakes.|dwell on the past
fall through|pv|The deal fell through at the last minute.|plans fall through
gloss over|pv|The report glosses over the most serious problems.|gloss over details
hammer out|pv|Negotiators hammered out a compromise after three days.|hammer out an agreement
iron out|pv|We still need to iron out a few technical details.|iron out difficulties
lay bare|pv|The investigation laid bare years of corruption.|lay bare the truth
mull over|pv|She took a week to mull over the job offer.|mull over a decision
pan out|pv|It's too early to say how the plan will pan out.|pan out well
phase out|pv|The firm plans to phase out single-use plastics by 2030.|phase out gradually
pore over|pv|Researchers pored over thousands of archived letters.|pore over documents
rein in|pv|The central bank moved to rein in inflation.|rein in spending
root out|pv|The new chief vowed to root out corruption in the department.|root out corruption
scale back|pv|Funding problems forced them to scale back the project.|scale back plans
shore up|pv|The government tried to shore up the failing banks.|shore up support
slough off|pv|He sloughed off the criticism and carried on.|slough off the past
smooth over|pv|She tried to smooth over the disagreement before the client arrived.|smooth over tensions
stave off|pv|Emergency loans helped stave off bankruptcy.|stave off collapse
steer clear of|pv|Investors should steer clear of speculative stocks.|steer clear of trouble
tide over|pv|A small loan tided them over until payday.|tide someone over
tone down|pv|The editor asked him to tone down the language in the article.|tone down criticism
usher in|pv|The invention of the printing press ushered in a new era.|usher in a new era
weed out|pv|Interviews are meant to weed out unsuitable candidates.|weed out weak candidates
wade through|pv|I had to wade through hundreds of pages of legal jargon.|wade through paperwork
zero in on|pv|Investigators zeroed in on a single suspect.|zero in on the problem
a double-edged sword|multi|Social media is a double-edged sword for young people.|prove a double-edged sword
the elephant in the room|multi|Nobody wanted to mention the elephant in the room: the budget deficit.|address the elephant in the room
a watershed moment|multi|The 2008 crisis was a watershed moment for global finance.|a watershed moment in history
a Pyrrhic victory|multi|Winning the case but losing the client was a Pyrrhic victory.|win a Pyrrhic victory
a Faustian bargain|multi|The firm made a Faustian bargain, trading long-term trust for quick profit.|strike a Faustian bargain
the tip of the iceberg|multi|The leaked emails were just the tip of the iceberg.|only the tip of the iceberg
a red herring|multi|The missing wallet turned out to be a red herring.|a classic red herring
a Trojan horse|multi|The free software proved to be a Trojan horse for spyware.|act as a Trojan horse
a Catch-22|multi|Needing experience to get a job that gives experience is a classic Catch-22.|a Catch-22 situation
a sea change|multi|The pandemic brought about a sea change in how we work.|a sea change in attitudes
a perfect storm|multi|Rising costs and falling demand created a perfect storm for the industry.|a perfect storm of
a necessary evil|multi|Many employees regard performance reviews as a necessary evil.|a necessary evil
the lesser of two evils|multi|Neither option was attractive, so she chose the lesser of two evils.|choose the lesser of two evils
a vicious circle|multi|Debt leads to stress, which leads to poor decisions: a vicious circle.|break the vicious circle
the thin end of the wedge|multi|Critics fear the pilot scheme is the thin end of the wedge.|the thin end of the wedge
a bone of contention|multi|The location of the new airport remains a bone of contention.|a major bone of contention
the last straw|multi|The missed deadline was the last straw for the client.|the final straw
a poisoned chalice|multi|The top job turned out to be a poisoned chalice.|a poisoned chalice
a Gordian knot|multi|Planners faced a Gordian knot of overlapping regulations.|cut the Gordian knot
a pipe dream|multi|Owning a house in the capital is a pipe dream for most graduates.|a mere pipe dream
a hard-and-fast rule|multi|There is no hard-and-fast rule for when to use the comma here.|hard-and-fast rules
a foregone conclusion|multi|The result of the election seemed a foregone conclusion.|a foregone conclusion
a moot point|multi|Whether it was legal is a moot point now that the building is gone.|a moot point
a tall order|multi|Finishing the report by Friday is a tall order.|a tall order
cut and dried|multi|The case is far from cut and dried.|cut and dried
touch and go|multi|It was touch and go whether the flight would take off in the storm.|touch and go
by and large|multi|By and large, the reforms have been well received.|by and large
at a loose end|multi|With the project finished, he found himself at a loose end.|be at a loose end
in the offing|multi|Rumours suggest a merger is in the offing.|something is in the offing
on tenterhooks|multi|We waited on tenterhooks for the exam results.|be on tenterhooks
cry wolf|fix|After so many false alarms, people stopped listening when he cried wolf.|cry wolf too often
bite the bullet|fix|The board decided to bite the bullet and cut jobs.|bite the bullet and
burn the midnight oil|fix|She burned the midnight oil to finish the thesis.|burn the midnight oil
hold sway|pol|Traditional values still hold sway in rural areas.|hold sway over
turn a blind eye|fix|Officials turned a blind eye to the illegal dumping.|turn a blind eye to
toe the line|fix|Employees who refuse to toe the line risk dismissal.|toe the party line
sit on the fence|opin|On this issue, the minister has been sitting on the fence.|sit on the fence
throw down the gauntlet|fix|The rival firm threw down the gauntlet with a much cheaper product.|throw down the gauntlet
rest on one's laurels|succ|After one hit album, the band could not afford to rest on its laurels.|rest on your laurels
cast aspersions|praise|It is unfair to cast aspersions on her integrity without evidence.|cast aspersions on
set a precedent|essay|The ruling sets a precedent for future cases.|set a dangerous precedent
tread a fine line|fix|Journalists must tread a fine line between informing and inflaming.|tread a fine line between
pay lip service to|fix|Many firms pay lip service to diversity but change little.|pay lip service to
play devil's advocate|opin|Let me play devil's advocate for a moment.|play devil's advocate
play it by ear|fix|We have no fixed plan, so we'll play it by ear.|play it by ear
nip in the bud|fix|Early intervention can nip problems in the bud.|nip it in the bud
draw a veil over|fix|Let us draw a veil over what happened next.|draw a veil over
come to a head|fix|Tensions between the two departments finally came to a head.|come to a head
hit the nail on the head|praise|Her analysis hit the nail on the head.|hit the nail on the head
read between the lines|fix|If you read between the lines, the memo is a warning.|read between the lines
at the behest of|formal|The study was commissioned at the behest of the ministry.|at the behest of
in lieu of|formal|Staff received a day off in lieu of overtime pay.|in lieu of
in abeyance|formal|The plan has been held in abeyance until funding is confirmed.|hold in abeyance
in tandem with|formal|The two agencies worked in tandem with local police.|work in tandem
in the wake of|formal|Security was tightened in the wake of the attack.|in the wake of
with impunity|crime|Hackers operated with impunity for years.|act with impunity
to all intents and purposes|link|To all intents and purposes, the project is finished.|to all intents and purposes
for the foreseeable future|link|Prices will remain high for the foreseeable future.|for the foreseeable future
notwithstanding|link|Notwithstanding these objections, the plan went ahead.|notwithstanding the fact that
inasmuch as|link|The study is useful inasmuch as it highlights gaps in the data.|inasmuch as
insofar as|link|The law is effective insofar as it is enforced.|insofar as
albeit|link|It was a success, albeit a modest one.|albeit briefly
hence|link|Demand is rising, hence the shortage of housing.|and hence
thereby|link|They cut costs, thereby increasing profits.|thereby allowing
whereby|link|A system whereby citizens vote online has been proposed.|a system whereby
conversely|contrast|Conversely, some firms benefited from the new tariffs.|but conversely
by the same token|contrast|By the same token, lower taxes do not always lead to growth.|by the same token
be that as it may|contrast|Be that as it may, the deadline cannot be moved.|be that as it may
all things considered|essay|All things considered, the trial was a success.|all things considered
on balance|essay|On balance, the benefits outweigh the costs.|on balance
by dint of|cause|She succeeded by dint of sheer hard work.|by dint of hard work
ramification|abs|The ramifications of the ruling will be felt for years.|far-reaching ramifications
juxtaposition|art|The film's juxtaposition of wealth and poverty is striking.|an uneasy juxtaposition
paradigm|abs|The discovery triggered a paradigm shift in physics.|paradigm shift
dichotomy|abs|The dichotomy between public and private life is increasingly blurred.|a false dichotomy
vicissitudes|abs|He survived the vicissitudes of political life for forty years.|the vicissitudes of life
exigency|abs|The exigencies of war forced the government to ration food.|the exigencies of
hubris|abs|His hubris led him to ignore every warning.|hubris and arrogance
largesse|abs|The museum depends on the largesse of private donors.|corporate largesse
munificence|abs|The library was built through the munificence of a local banker.|the munificence of
equanimity|feel|She received the news with remarkable equanimity.|with equanimity
trepidation|feel|He opened the letter with some trepidation.|with trepidation
ennui|feel|A deep ennui settled over the town in the long winter.|a sense of ennui
umbrage|feel|She took umbrage at the suggestion that she was late.|take umbrage at
schadenfreude|feel|He felt a flicker of schadenfreude at his rival's failure.|a hint of schadenfreude
rancour|feel|The dispute was settled without rancour.|without rancour
animus|feel|There is no personal animus between the two leaders.|personal animus
equivocation|abs|The inquiry demanded a straight answer, free of equivocation.|without equivocation
disquiet|feel|The proposal caused widespread disquiet among staff.|growing disquiet
magnanimity|char|He showed great magnanimity in forgiving his rival.|show magnanimity
probity|char|Her probity as a judge was never questioned.|financial probity
rectitude|char|He was known for his moral rectitude.|moral rectitude
sagacity|char|The report praised the sagacity of the early investors.|political sagacity
temerity|char|He had the temerity to ask for a pay rise on his first day.|have the temerity to
tenacity|char|Her tenacity eventually won over the sceptics.|show tenacity
acumen|career|Her business acumen turned a failing shop into a chain.|business acumen
gravitas|career|The role demands someone of real gravitas.|intellectual gravitas
panache|char|She delivered the speech with great panache.|with panache
sangfroid|char|The pilot kept his sangfroid throughout the emergency.|keep your sangfroid
bonhomie|char|The party was full of warmth and bonhomie.|an air of bonhomie
chicanery|crime|The firm was accused of legal chicanery.|political chicanery
malfeasance|crime|The mayor was removed from office for malfeasance.|corporate malfeasance
peculation|crime|The clerk was jailed for the peculation of public funds.|peculation of funds
perjury|crime|He was charged with perjury after lying under oath.|commit perjury
embezzlement|crime|She was convicted of embezzlement of over two million pounds.|charged with embezzlement
nepotism|pol|Accusations of nepotism followed the appointment of his nephew.|accusations of nepotism
cronyism|pol|The contracts were awarded amid allegations of cronyism.|political cronyism
sinecure|career|The post was a comfortable sinecure for the minister's friend.|a cushy sinecure
gerrymander|pol|The party was accused of trying to gerrymander the districts.|gerrymander a district
filibuster|pol|The senator tried to block the bill with a filibuster.|conduct a filibuster
hegemony|pol|The empire established hegemony over the entire region.|global hegemony
realpolitik|pol|The deal was a classic piece of realpolitik.|a policy of realpolitik
détente|pol|The two powers entered a period of détente.|a period of détente
suzerainty|pol|The province remained under the suzerainty of the empire.|under the suzerainty of
plebiscite|pol|The region voted for independence in a plebiscite.|hold a plebiscite
demagogue|pol|The demagogue exploited public fears to win votes.|a populist demagogue
oligarchy|pol|Critics describe the country as an oligarchy rather than a democracy.|a ruling oligarchy
autarky|fin|Total autarky is impossible for a small, trade-dependent economy.|economic autarky
fiduciary|fin|Directors have a fiduciary duty to shareholders.|fiduciary duty
liquidity|fin|The bank faced a severe liquidity crisis.|a liquidity crisis
solvency|fin|Auditors raised concerns about the firm's solvency.|maintain solvency
insolvent|fin|The retailer was declared insolvent last month.|declared insolvent
arbitrage|fin|Traders profit from arbitrage between the two exchanges.|currency arbitrage
amortise|fin|The loan will be amortised over twenty years.|amortise a loan
leverage|fin|The fund used heavy leverage to boost returns.|highly leveraged
capitulate|biz|After months of pressure, the board capitulated to the investors' demands.|capitulate to demands
consolidate|biz|The two banks plan to consolidate their operations.|consolidate a position
diversify|biz|The firm diversified into renewable energy.|diversify into
disintermediation|biz|Online platforms have driven disintermediation in the travel industry.|driven by disintermediation
due diligence|biz|The buyer carried out thorough due diligence before signing.|conduct due diligence
economies of scale|biz|Larger producers benefit from economies of scale.|achieve economies of scale
bottom line|biz|Every decision is judged by its effect on the bottom line.|affect the bottom line
a paradigm shift|biz|Cloud computing triggered a paradigm shift in the software industry.|a paradigm shift in
headwinds|biz|The airline faces strong headwinds from rising fuel costs.|face headwinds
tailwind|biz|Falling interest rates gave the housing market a tailwind.|a tailwind for
stakeholder|biz|The plan was discussed with all key stakeholders.|key stakeholders
scalable|biz|The start-up needs a scalable business model.|a scalable solution
leaner|biz|The restructuring left the company leaner and more efficient.|a leaner organisation
onerous|biz|Small firms find the reporting requirements onerous.|an onerous burden
punitive|crime|The treaty imposed punitive reparations on the defeated nation.|punitive measures
draconian|crime|Critics called the new surveillance law draconian.|draconian measures
statute|crime|The practice is prohibited by statute.|statute of limitations
litigious|crime|The litigious climate makes doctors cautious about every decision.|a litigious society
indictment|crime|The report is a damning indictment of the system.|an indictment of
extradite|crime|The suspect was extradited to face trial abroad.|extradite a suspect
clemency|crime|The prisoner appealed for clemency.|grant clemency
acquit|crime|The jury acquitted him of all charges.|acquitted of
recidivism|crime|The programme has reduced recidivism among young offenders.|reduce recidivism
culpability|crime|The inquiry established the company's culpability for the accident.|establish culpability
ex gratia|fin|The firm made an ex gratia payment to the families.|an ex gratia payment
pro bono|career|The firm takes on several cases pro bono each year.|work pro bono
mitigating|crime|The judge took mitigating circumstances into account.|mitigating circumstances
tenable|essay|Such a position is no longer tenable in light of the new evidence.|a tenable argument
cogent|essay|She presented a cogent case for reform.|a cogent argument
corollary|essay|A rise in life expectancy has, as a corollary, an ageing workforce.|a natural corollary
caveat|essay|The study comes with one important caveat.|with the caveat that
axiom|essay|It is an axiom of economics that resources are scarce.|a basic axiom
postulate|essay|Einstein postulated that the speed of light is constant.|postulate a theory
empirical|sci|The theory lacks empirical support.|empirical evidence
heuristic|sci|Engineers used a simple heuristic to estimate the cost.|a heuristic approach
nomenclature|sci|The nomenclature of the species is still disputed.|botanical nomenclature
anomaly|sci|The data contained one puzzling anomaly.|a statistical anomaly
corroboration|sci|The claim needs independent corroboration.|seek corroboration
replicate|sci|Other labs failed to replicate the results.|replicate findings
confounding|sci|Age is a confounding variable in the study.|a confounding factor
attrition|sci|High attrition among participants weakened the study.|rate of attrition
seminal|sci|Her seminal paper launched an entire field of research.|a seminal work
paradigmatic|sci|The case is paradigmatic of a wider problem.|a paradigmatic example
algorithmic|sci|Algorithmic bias can reinforce existing inequalities.|algorithmic bias
obsolescence|sci|Planned obsolescence forces consumers to replace devices quickly.|planned obsolescence
dystopian|art|The novel paints a dystopian vision of a surveilled society.|a dystopian future
allegory|art|The story is an allegory of the rise of fascism.|a political allegory
pathos|art|The film is full of pathos without becoming sentimental.|a sense of pathos
verisimilitude|art|The details lend the novel a startling verisimilitude.|an air of verisimilitude
pastiche|art|The building is a pastiche of several architectural styles.|a pastiche of
magnum opus|art|The symphony is widely regarded as the composer's magnum opus.|his magnum opus
oeuvre|art|Her early films are a small part of her vast oeuvre.|the complete oeuvre
avant-garde|art|The gallery showcases avant-garde artists from across Europe.|an avant-garde movement
cadence|art|The poet reads in a slow, hypnotic cadence.|the cadence of speech
denouement|art|The denouement of the film ties up every loose end.|the final denouement
hagiography|media|The biography reads more like a hagiography than a balanced account.|a hagiography of
polemic|media|His article was a polemic against the education system.|a fierce polemic
sensationalism|media|Tabloid sensationalism distorted the public's view of the case.|media sensationalism
disinformation|media|Social platforms struggle to contain online disinformation.|a disinformation campaign
spin|media|The government's spin did little to calm the public.|political spin
exposé|media|The newspaper published an exposé of corruption in the police force.|a damning exposé
vox pop|media|The programme opened with a vox pop from shoppers on the high street.|a vox pop
ephemeral|adj|Fame in the age of social media is often ephemeral.|ephemeral nature
anthropogenic|env|Anthropogenic emissions are the main driver of warming.|anthropogenic climate change
biodiversity|env|Draining wetlands has devastated local biodiversity.|loss of biodiversity
rewilding|env|Rewilding schemes have brought beavers back to British rivers.|a rewilding project
carbon sink|env|Mature forests act as a vital carbon sink.|act as a carbon sink
tipping point|env|Scientists warn that the ice sheet may be approaching a tipping point.|reach a tipping point
unsustainable|env|The current rate of consumption is unsustainable.|environmentally unsustainable
profligacy|env|The report condemned the profligacy of wealthy nations in using energy.|environmental profligacy
precarity|glob|Gig work has increased economic precarity for young adults.|economic precarity
destitution|glob|War has pushed millions into destitution.|abject destitution
famine|glob|Drought-induced famine threatens the entire region.|widespread famine
displacement|glob|Conflict has caused mass displacement across the border.|forced displacement
xenophobia|glob|Politicians were urged to speak out against rising xenophobia.|rising xenophobia
atrophy|med|Muscles atrophy quickly without use.|muscular atrophy
palliative|med|The hospice provides palliative care for terminally ill patients.|palliative care
prognosis|med|The prognosis for early-stage patients is good.|a poor prognosis
comorbidity|med|Comorbidity makes the treatment of older patients more complex.|a common comorbidity
iatrogenic|med|Some complications are iatrogenic, caused by the treatment itself.|iatrogenic harm
benign|med|The tumour turned out to be benign.|a benign condition
virulent|med|A virulent strain of the virus spread rapidly through the ward.|a virulent strain
chronic|med|Chronic stress takes a heavy toll on the heart.|chronic illness
remission|med|After two years of treatment, the cancer is in remission.|go into remission
pedagogy|edu|The course focuses on critical pedagogy and learner autonomy.|innovative pedagogy
erudite|edu|The erudite professor could quote Homer from memory.|an erudite scholar
tenure|edu|Young academics struggle to secure tenure.|gain tenure
thesis|edu|Her thesis challenges the conventional view of the period.|defend a thesis
rigour|edu|Academic rigour is the hallmark of the department.|intellectual rigour
as nimble as a goat|simile|The old guide was as nimble as a goat on the mountain trails.|as nimble as a goat
as dry as dust|simile|The lecture was as dry as dust.|dry as dust
as sure as eggs is eggs|simile|He'll be late, as sure as eggs is eggs.|sure as eggs is eggs
like a fish out of water|simile|At the formal dinner, she felt like a fish out of water.|feel like a fish out of water
like a bull in a china shop|simile|He barged into the delicate negotiation like a bull in a china shop.|like a bull in a china shop
like water off a duck's back|simile|Criticism runs off him like water off a duck's back.|like water off a duck's back
`;

const read = (n) => {
  try { return JSON.parse(fs.readFileSync(`paid-content/${n}.json`, "utf8")); }
  catch { return []; }
};
const norm = (s) => String(s).toLowerCase().replace(/[’‘]/g, "'").replace(/^[«»"'.,!?;:()]+|[«»"'.,!?;:()]+$/g, "").trim();

const file = "paid-content/vocab_in_use_words.json";
const list = read("vocab_in_use_words");
const have = new Set([...list, ...read("daily_words"), ...read("slang_words")].map((w) => norm(w.en)));
const KNOWN = new Set(list.map((w) => w.category));

let id = Math.max(799999, ...list.filter((w) => w.id >= 800000).map((w) => w.id)) + 1;
let added = 0, skipped = 0;
for (const line of C2.trim().split("\n")) {
  const [en, key, example, collocation] = line.split("|").map((s) => s.trim());
  if (!en || !key || !example) throw new Error("خطِ ناقص: " + line);
  const category = ALIAS[key];
  if (!category || !KNOWN.has(category)) throw new Error("دسته‌ی نامعتبر: " + line);
  if (have.has(norm(en))) { skipped++; continue; }
  list.push({ id: id++, level: "C2", pos: "other", en, fa: "", example, collocation: collocation || "", category });
  have.add(norm(en));
  added++;
}
fs.writeFileSync(file, JSON.stringify(list));
console.log("vocab_in_use_words:", list.length, "| C2 اضافه‌شده:", added, "| تکراری (رد شد):", skipped);
