#[macro_use]
extern crate pretty_assertions;

#[cfg(test)]
mod insert_doc_syntax_highlighting {
    use bumpalo::Bump;
    use roc_can::env::Env;
    use roc_can::scope::Scope;
    use roc_collections::all::MutMap;
    use roc_docs::syntax_highlight_code;
    use roc_module::symbol::{IdentIds, Interns, ModuleIds};
    use roc_types::subs::VarStore;

    fn expect_html(code_str: &str, want: &str) {
        let code_block_arena = Bump::new();

        let mut code_block_buf = bumpalo::collections::String::new_in(&code_block_arena);
        match syntax_highlight_code(&code_block_arena, &mut code_block_buf, code_str) {
            Ok(highlighted_code_str) => {
                assert_eq!(highlighted_code_str, want);
            }
            Err(syntax_error) => {
                panic!("Unexpected parse failure when parsing this for rendering in docs:\n\n{}\n\nParse error was:\n\n{:?}\n\n", code_str, syntax_error)
            }
        };
    }

    #[test]
    fn simple_code_block() {
        expect_html(
            r#"
                f = \x, y ->
                    b = 6
                    c
                    
                "string"
            "#,
            r#"
            <div class="syntax-var">x</div> <div class="syntax-operator">:</div> <div class="syntax-type">Nat</div>
            <div class="syntax-var">x</div> <div class="syntax-operator">=</div>
                <div class="syntax-number">4</div>
                
            <div class="syntax-number">2</div>
        "#,
        );
    }
    // #[test]
    // fn simple_code_block() {
    //     expect_html(
    //         r#"
    //             x : Nat
    //             x =
    //                 4
    //
    //             2
    //         "#,
    //         r#"
    //         <div class="syntax-var">x</div> <div class="syntax-operator">:</div> <div class="syntax-type">Nat</div>
    //         <div class="syntax-var">x</div> <div class="syntax-operator">=</div>
    //             <div class="syntax-number">4</div>
    //
    //         <div class="syntax-number">2</div>
    //     "#,
    //     );
    // }
}
