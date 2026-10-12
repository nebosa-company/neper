# Small multilingual corpora for scripts/gen_charset_test.py: TRAIN builds the byte-frequency tables of
# e.text.encoding.detect_legacy, TEST is held out (no sentence appears in both).
TRAIN = {
    "fr": "Le petit garçon a mangé une pomme près de la rivière, puis il est rentré à la maison où sa mère l'attendait. "
          "Être ou ne pas être, voilà la question qui préoccupe les élèves après l'école. "
          "Nous avons décidé d'organiser une fête pour célébrer l'arrivée de l'été, même s'il pleut déjà. "
          "Les étudiants préfèrent étudier à la bibliothèque où il y a beaucoup de livres intéressants. "
          "Où êtes-vous allés hier soir ? Ça fait déjà longtemps que nous n'avons pas écouté cette chanson. "
          "Le café était très chaud, mais le gâteau était délicieux et très léger. Il a dû être très déçu.",
    "de": "Die Kinder spielen im Garten, während die Mütter über schöne Möbel und größere Häuser sprechen. "
          "Übermorgen fahren wir nach München, um unsere Großeltern zu besuchen und gemeinsam zu frühstücken. "
          "Für die Prüfung müssen wir noch viele Übungen lösen, aber das Wetter ist zu schön zum Lernen. "
          "Ärzte empfehlen, täglich genügend Wasser zu trinken und regelmäßig spazieren zu gehen. "
          "Der Bäcker verkauft frische Brötchen, süße Törtchen und knusprige Brezeln für wenig Geld. "
          "Wir müssen draußen warten, weil die Türen geschlossen sind und niemand öffnet.",
    "es": "El niño comió una manzana junto al río y después volvió a casa, donde su madre lo esperaba. "
          "Mañana por la mañana iremos a la montaña para disfrutar del aire fresco y de la tranquilidad. "
          "¿Qué quieres hacer esta noche? Podríamos cenar en el restaurante que está cerca de la estación. "
          "La señora compró cinco kilos de naranjas y también unas cuantas piñas muy dulces. "
          "Tenía mucho sueño después del viaje, así que se fue a dormir sin cenar. "
          "Los jóvenes españoles prefieren más música, pero algunos sólo leen periódicos.",
    "pt": "O menino comeu uma maçã perto do rio e depois voltou para casa, onde a mãe o esperava. "
          "Amanhã de manhã vamos à praia para aproveitar o sol e a água fresca com os nossos irmãos. "
          "A informação está disponível na internet, mas a explicação não é muito clara para os alunos. "
          "Não sei se vou conseguir terminar o trabalho antes da reunião, porque ainda tenho muitas coisas. "
          "Às vezes é difícil compreender a situação política, sobretudo quando há tantas opiniões. "
          "A avó preparou pão, feijão e também uns doces tradicionais para a celebração.",
    "it": "Il bambino ha mangiato una mela vicino al fiume e poi è tornato a casa, dove la mamma lo aspettava. "
          "Perché non andiamo al mare domani? Potremmo partire già la mattina presto, così avremmo più tempo. "
          "La città è piena di turisti, però la qualità della vita è più alta di quanto si pensi. "
          "Così è andata, e purtroppo nessuno può tornare indietro per cambiare ciò che è già accaduto. "
          "L'università ha aperto nuovi corsi di perfezionamento che offrono maggiori possibilità. "
          "Più tardi mangeremo un gelato in piazza, poi andremo a casa a riposare.",
    "sv": "Pojken åt ett äpple vid ån och gick sedan hem, där hans mamma väntade på honom. "
          "På sommaren åker vi till stugan i skogen för att bada, fiska och äta jordgubbar med grädde. "
          "Det är svårt att förstå varför människor inte lyssnar, även när det gäller viktiga frågor. "
          "Många svenskar tycker om att fira midsommar med sill, potatis och snaps vid långa bord. "
          "Min syster bor i Göteborg och arbetar som lärare på en skola nära älven. "
          "Hon köpte nya skor, en röd klänning och två böcker om länder långt härifrån.",
    "da": "Drengen spiste et æble ved åen og gik så hjem, hvor hans mor ventede på ham. "
          "Vi skal på ferie til Jylland i sommer, og børnene glæder sig til at bade i havet og spise is. "
          "Det er svært at forstå, hvorfor så mange mennesker ikke gider læse aviser længere. "
          "Min søster bor i København og arbejder som lærer på en skole tæt på søerne. "
          "Københavnerne cykler næsten overalt, også når det regner og blæser gevaldigt. "
          "Hun købte nye sko, en rød kjole og to bøger om lande langt væk fra Danmark.",
    "nl": "De jongen at een appel bij de rivier en ging daarna naar huis, waar zijn moeder op hem wachtte. "
          "Morgen gaan we naar de zee om te zwemmen en ijs te eten, hoewel het weer misschien tegenvalt. "
          "Ik heb een boek gelezen over geschiedenis dat mij zeer is bevallen, ook al was het wat lang. "
          "Waar zijn de kinderen gebleven? Ze zouden om vijf uur thuis zijn voor het avondeten. "
          "Het café op de hoek serveert de beste koffie en ook heerlijke appeltaart met slagroom. "
          "Mijn broer woont in Rotterdam en werkt als ingenieur bij een grote haven.",
    "en": "The boy ate an apple by the river and then walked home, where his mother was waiting for him. "
          "It’s a beautiful day, and “the best things in life are free” – or so they say. "
          "She paid €20 for the ticket — a lot of money for a short trip to the naïve café. "
          "The company announced • record profits • new offices • and a résumé of its history.",
    "pl": "Chłopiec zjadł jabłko nad rzeką, a potem wrócił do domu, gdzie czekała na niego matka. "
          "Jutro rano pojedziemy w góry, żeby odpocząć od miejskiego hałasu i nacieszyć się świeżym powietrzem. "
          "Źródło tej informacji jest niepewne, dlatego nie możemy jej wykorzystać w naszym raporcie. "
          "Mój brat mieszka w Łodzi i pracuje jako nauczyciel w szkole średniej niedaleko dworca. "
          "Żółć, ząb i łódź to słowa, które cudzoziemcom sprawiają wiele kłopotu podczas nauki. "
          "Wszyscy się cieszyli, że egzaminy zostały przesunięte na przyszły tydzień.",
    "cs": "Chlapec snědl jablko u řeky a potom se vrátil domů, kde na něj čekala matka. "
          "Zítra ráno pojedeme do hor, abychom si odpočinuli od městského ruchu a nadýchali se čerstvého vzduchu. "
          "Příští týden budeme psát důležitou zkoušku, proto se musíme pořádně připravit. "
          "Můj bratr bydlí v Plzni a pracuje jako učitel na střední škole poblíž nádraží. "
          "Děti si hrály na zahradě, zatímco rodiče připravovali oběd a povídali si o životě. "
          "Řeka se vylila z břehů, a tak museli všichni obyvatelé opustit své domovy.",
    "hu": "A fiú megevett egy almát a folyó mellett, aztán hazament, ahol az anyja várta. "
          "Holnap reggel a hegyekbe megyünk, hogy kipihenjük magunkat a város zaja után. "
          "Szeretnék egy kávét inni, de előbb be kell fejeznem ezt a hosszú és nehéz feladatot. "
          "A nővérem Budapesten él, és egy iskolában tanít a Duna közelében. "
          "Őszintén örülök, hogy végre eljöttetek hozzánk látogatóba, mert régen láttuk egymást. "
          "Különösen szép a tavasz, amikor a fák virágoznak és a madarak énekelnek.",
    "ro": "Băiatul a mâncat un măr lângă râu și apoi s-a întors acasă, unde mama îl aștepta. "
          "Mâine dimineață vom merge la munte ca să ne odihnim după zgomotul orașului și să respirăm aer curat. "
          "Fiecare om are dreptul să fie ascultat, însă puțini știu cu adevărat să asculte. "
          "Sora mea locuiește în București și lucrează ca profesoară într-o școală de lângă gară. "
          "Țara noastră este frumoasă, iar oamenii sunt primitori și întotdeauna dornici să ajute.",
    "ru": "Мальчик съел яблоко возле реки, а потом пошёл домой, где его ждала мама. "
          "Завтра утром мы поедем в горы, чтобы отдохнуть от городского шума и подышать свежим воздухом. "
          "Я не знаю, смогу ли я закончить эту работу до собрания, потому что у меня ещё много дел. "
          "Моя сестра живёт в Москве и работает учителем в школе недалеко от вокзала. "
          "Это очень интересная книга о жизни и истории нашей страны, которую стоит прочитать каждому. "
          "Погода сегодня прекрасная, поэтому дети играют во дворе, а родители разговаривают на скамейке.",
    "uk": "Хлопчик з'їв яблуко біля річки, а потім пішов додому, де його чекала мама. "
          "Завтра вранці ми поїдемо в гори, щоб відпочити від міського шуму та подихати свіжим повітрям. "
          "Моя сестра живе в Києві й працює вчителькою в школі неподалік від вокзалу. "
          "Це дуже цікава книжка про життя та історію нашої країни, яку варто прочитати кожному. "
          "Українська мова є однією з найкрасивіших мов світу, і ми маємо її берегти.",
    "bg": "Момчето изяде една ябълка край реката и после се прибра вкъщи, където майка му го чакаше. "
          "Утре сутринта ще отидем в планината, за да си починем от градския шум и да подишаме чист въздух. "
          "Сестра ми живее в София и работи като учителка в училище близо до гарата. "
          "Това е много интересна книга за живота и историята на нашата страна, която си струва да се прочете. "
          "Времето днес е чудесно, затова децата играят в двора, а родителите си говорят на пейката.",
    "el": "Το αγόρι έφαγε ένα μήλο δίπλα στο ποτάμι και μετά γύρισε στο σπίτι, όπου το περίμενε η μητέρα του. "
          "Αύριο το πρωί θα πάμε στο βουνό για να ξεκουραστούμε από τον θόρυβο της πόλης και να αναπνεύσουμε καθαρό αέρα. "
          "Η αδελφή μου μένει στην Αθήνα και δουλεύει ως δασκάλα σε ένα σχολείο κοντά στον σταθμό. "
          "Είναι ένα πολύ ενδιαφέρον βιβλίο για τη ζωή και την ιστορία της χώρας μας που αξίζει να διαβαστεί. "
          "Ο καιρός σήμερα είναι υπέροχος, γι' αυτό τα παιδιά παίζουν στην αυλή και οι γονείς μιλούν στο παγκάκι.",
    "tr": "Çocuk nehrin yanında bir elma yedi ve sonra annesinin beklediği eve geri döndü. "
          "Yarın sabah şehrin gürültüsünden uzaklaşmak ve temiz hava solumak için dağlara gideceğiz. "
          "Kız kardeşim İstanbul'da yaşıyor ve istasyonun yakınındaki bir okulda öğretmen olarak çalışıyor. "
          "Bu, ülkemizin tarihi ve yaşamı hakkında okunmaya değer çok ilginç bir kitap. "
          "Bugün hava çok güzel, bu yüzden çocuklar bahçede oynuyor, ebeveynler de bankta sohbet ediyor.",
    "he": "הילד אכל תפוח ליד הנהר ואחר כך חזר הביתה, שם חיכתה לו אמו. "
          "מחר בבוקר ניסע להרים כדי לנוח מרעש העיר ולנשום אוויר צח. "
          "אחותי גרה בירושלים ועובדת כמורה בבית ספר ליד תחנת הרכבת. "
          "זה ספר מעניין מאוד על החיים וההיסטוריה של המדינה שלנו, וכדאי שכל אחד יקרא אותו. "
          "מזג האוויר היום נהדר, ולכן הילדים משחקים בחצר וההורים מדברים על הספסל.",
    "ar": "أكل الولد تفاحة بجانب النهر ثم عاد إلى البيت حيث كانت أمه تنتظره. "
          "في صباح الغد سنذهب إلى الجبال لنستريح من ضجيج المدينة ونتنفس هواء نقيا. "
          "تسكن أختي في القاهرة وتعمل معلمة في مدرسة قريبة من المحطة. "
          "هذا كتاب مثير للاهتمام عن حياة بلدنا وتاريخه ويستحق أن يقرأه الجميع. "
          "الطقس اليوم رائع، لذلك يلعب الأطفال في الفناء ويتحدث الآباء على المقعد.",
    "lt": "Berniukas suvalgė obuolį prie upės ir paskui grįžo namo, kur jo laukė mama. "
          "Rytoj ryte važiuosime į kalnus pailsėti nuo miesto triukšmo ir pakvėpuoti grynu oru. "
          "Mano sesuo gyvena Vilniuje ir dirba mokytoja mokykloje netoli stoties. "
          "Tai labai įdomi knyga apie mūsų šalies gyvenimą ir istoriją, kurią verta perskaityti kiekvienam. "
          "Šiandien oras puikus, todėl vaikai žaidžia kieme, o tėvai kalbasi ant suoliuko.",
    "lv": "Zēns apēda ābolu pie upes un tad devās mājup, kur viņu gaidīja māte. "
          "Rīt no rīta brauksim uz kalniem, lai atpūstos no pilsētas trokšņa un ieelpotu tīru gaisu. "
          "Mana māsa dzīvo Rīgā un strādā par skolotāju skolā netālu no stacijas. "
          "Šī ir ļoti interesanta grāmata par mūsu zemes dzīvi un vēsturi, kuru vērts izlasīt ikvienam. "
          "Šodien laiks ir lielisks, tāpēc bērni spēlējas pagalmā, bet vecāki sarunājas uz soliņa.",
}

TEST = {
    "fr": ["Mon frère a acheté une maison près de Lyon, et nous irons le voir à Noël, s'il fait beau.",
           "Il faut que tu m'aides à préparer le dîner : j'ai oublié d'acheter les légumes et le pain.",
           "Cet été, les enfants ont découvert la côte bretonne, ses falaises et ses petits ports de pêche.",
           "Après la réunion, nous avons déjeuné dans un café où l'on sert des crêpes très appréciées."],
    "de": ["Mein Bruder hat ein Haus in der Nähe von Köln gekauft, und wir besuchen ihn zu Weihnachten.",
           "Könntest du mir bitte helfen, das Abendessen vorzubereiten? Ich habe das Gemüse vergessen.",
           "Im Sommer haben die Kinder die Küste entdeckt, mit ihren Klippen und kleinen Fischerdörfern.",
           "Nach der Besprechung aßen wir in einem Café, das für seine Pfannkuchen und Süßigkeiten bekannt ist."],
    "es": ["Mi hermano compró una casa cerca de Sevilla y la visitaremos en Navidad si hace buen tiempo.",
           "Necesito que me ayudes a preparar la cena: me olvidé de comprar las verduras y el pan.",
           "Este verano los niños descubrieron la costa gallega, con sus acantilados y sus pequeños puertos.",
           "Después de la reunión almorzamos en un café donde sirven unos churros muy apreciados."],
    "pt": ["O meu irmão comprou uma casa perto de Coimbra e vamos visitá-lo no Natal, se fizer bom tempo.",
           "Preciso que me ajudes a preparar o jantar: esqueci-me de comprar os legumes e o pão.",
           "Neste verão as crianças descobriram a costa algarvia, com as suas falésias e pequenos portos.",
           "Depois da reunião almoçámos num café onde servem uns pastéis de nata muito apreciados."],
    "it": ["Mio fratello ha comprato una casa vicino a Firenze e andremo a trovarlo a Natale, se farà bel tempo.",
           "Ho bisogno che tu mi aiuti a preparare la cena: ho dimenticato di comprare la verdura e il pane.",
           "Quest'estate i bambini hanno scoperto la costa ligure, con le sue scogliere e i piccoli porti.",
           "Dopo la riunione abbiamo pranzato in un caffè dove servono dei dolci molto apprezzati."],
    "sv": ["Min bror köpte ett hus nära Uppsala och vi åker dit till jul om vädret tillåter.",
           "Du måste hjälpa mig att laga middag: jag glömde köpa grönsaker och bröd i affären.",
           "I somras upptäckte barnen västkusten med dess klippor och små fiskelägen.",
           "Efter mötet åt vi lunch på ett kafé där man serverar kanelbullar som är mycket omtyckta."],
    "da": ["Min bror købte et hus nær Aarhus, og vi tager derhen til jul, hvis vejret er godt.",
           "Du må hjælpe mig med at lave aftensmad: jeg glemte at købe grøntsager og brød.",
           "I sommers opdagede børnene vestkysten med dens klitter og små fiskerlejer.",
           "Efter mødet spiste vi frokost på en café, hvor man serverer rugbrød med pålæg."],
    "nl": ["Mijn broer heeft een huis gekocht bij Utrecht en we gaan er met kerst op bezoek als het weer goed is.",
           "Je moet me helpen met het avondeten: ik ben vergeten groenten en brood te kopen.",
           "Deze zomer ontdekten de kinderen de kust met zijn duinen en kleine vissersdorpen.",
           "Na de vergadering aten we lunch in een café waar ze heerlijke pannenkoeken serveren."],
    "en": ["He said “hello” to everyone – and that’s all he said — before leaving for the café.",
           "The price rose by €5 and the fiancée’s “naïve” début surprised the résumé readers."],
    "pl": ["Mój brat kupił dom koło Krakowa i pojedziemy do niego na święta, jeśli pogoda dopisze.",
           "Musisz mi pomóc przygotować kolację: zapomniałem kupić warzywa i chleb w sklepie.",
           "Tego lata dzieci odkryły wybrzeże, jego klify i małe porty rybackie nad Bałtykiem.",
           "Po spotkaniu zjedliśmy obiad w kawiarni, w której podają bardzo cenione pączki."],
    "cs": ["Můj bratr koupil dům poblíž Brna a pojedeme za ním na Vánoce, pokud bude hezké počasí.",
           "Musíš mi pomoci připravit večeři: zapomněl jsem koupit zeleninu a chléb v obchodě.",
           "Letos v létě děti objevily pobřeží, jeho útesy a malé rybářské přístavy.",
           "Po schůzce jsme obědvali v kavárně, kde podávají velmi oblíbené koláče."],
    "hu": ["A bátyám vett egy házat Szeged közelében, és karácsonykor meglátogatjuk, ha jó idő lesz.",
           "Segítened kell nekem a vacsora elkészítésében: elfelejtettem zöldséget és kenyeret venni.",
           "Idén nyáron a gyerekek felfedezték a partot, a sziklákat és a kis halászfalvakat.",
           "A megbeszélés után egy kávézóban ebédeltünk, ahol nagyon kedvelt süteményeket szolgálnak fel."],
    "ro": ["Fratele meu a cumpărat o casă lângă Cluj și îl vom vizita de Crăciun dacă vremea va fi bună.",
           "Trebuie să mă ajuți să pregătesc cina: am uitat să cumpăr legumele și pâinea de la magazin.",
           "Vara aceasta copiii au descoperit litoralul, cu falezele și porturile sale mici de pescari."],
    "ru": ["Мой брат купил дом недалеко от Казани, и мы поедем к нему на Новый год, если погода позволит.",
           "Ты должен помочь мне приготовить ужин: я забыл купить овощи и хлеб в магазине.",
           "Этим летом дети открыли для себя побережье с его скалами и маленькими рыбацкими портами.",
           "После собрания мы пообедали в кафе, где подают очень любимые всеми блины со сметаной."],
    "uk": ["Мій брат купив будинок поблизу Львова, і ми поїдемо до нього на Різдво, якщо погода дозволить.",
           "Ти маєш допомогти мені приготувати вечерю: я забув купити овочі та хліб у магазині."],
    "bg": ["Брат ми купи къща близо до Пловдив и ще го посетим по Коледа, ако времето позволи.",
           "Трябва да ми помогнеш да приготвя вечерята: забравих да купя зеленчуци и хляб от магазина."],
    "el": ["Ο αδελφός μου αγόρασε ένα σπίτι κοντά στη Θεσσαλονίκη και θα τον επισκεφθούμε τα Χριστούγεννα.",
           "Πρέπει να με βοηθήσεις να ετοιμάσω το δείπνο: ξέχασα να αγοράσω λαχανικά και ψωμί από το μαγαζί."],
    "tr": ["Kardeşim Ankara yakınlarında bir ev satın aldı ve hava güzel olursa yılbaşında onu ziyaret edeceğiz.",
           "Akşam yemeğini hazırlamama yardım etmelisin: sebzeleri ve ekmeği almayı unuttum."],
    "he": ["אחי קנה בית ליד חיפה ונבקר אותו בחג אם יהיה מזג אוויר טוב.",
           "אתה צריך לעזור לי להכין את ארוחת הערב: שכחתי לקנות ירקות ולחם בחנות."],
    "ar": ["اشترى أخي بيتا قرب الإسكندرية وسنزوره في العيد إذا كان الطقس جميلا.",
           "يجب أن تساعدني في تحضير العشاء: لقد نسيت أن أشتري الخضار والخبز من المتجر."],
    "lt": ["Mano brolis nusipirko namą netoli Kauno ir mes aplankysime jį per Kalėdas, jei oras bus geras.",
           "Tu turi man padėti paruošti vakarienę: pamiršau nupirkti daržovių ir duonos parduotuvėje."],
    "lv": ["Mans brālis nopirka māju netālu no Liepājas, un mēs apciemosim viņu Ziemassvētkos, ja laiks būs labs.",
           "Tev jāpalīdz man pagatavot vakariņas: es aizmirsu nopirkt dārzeņus un maizi veikalā."],
}

# charset (python codec name, label used by the module) -> languages it is trained and tested on
CHARSETS = [
    ("cp1252",     "windows-1252", ["fr", "de", "es", "pt", "it", "sv", "da", "nl", "en"]),
    ("cp1250",     "windows-1250", ["pl", "cs", "hu", "ro"]),
    ("iso8859-2",  "iso-8859-2",   ["pl", "cs", "hu", "ro"]),
    ("cp1251",     "windows-1251", ["ru", "uk", "bg"]),
    ("koi8-r",     "koi8-r",       ["ru"]),
    ("iso8859-5",  "iso-8859-5",   ["ru", "bg"]),
    ("cp866",      "ibm866",       ["ru"]),
    ("iso8859-7",  "iso-8859-7",   ["el"]),
    ("cp1254",     "windows-1254", ["tr"]),
    ("cp1255",     "windows-1255", ["he"]),
    ("cp1256",     "windows-1256", ["ar"]),
    ("cp1257",     "windows-1257", ["lt", "lv"]),
]
