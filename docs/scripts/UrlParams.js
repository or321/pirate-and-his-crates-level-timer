let UrlParams = function(){
    const searchParams = new URLSearchParams(window.location.search);

    let _texturesFile = function() {
        let texturesParam = "0";
        if (searchParams.has("textures")){
            texturesParam = searchParams.get("textures");
        }

        return "A-Pirate-and-his-Crates_texture_" + texturesParam + ".png";
    }

    return {
        texturesFile: _texturesFile()
    };

}();