Stencil Coprocessor
===================

このリポジトリには、ACRi ブログでのコース (連載) の1つである「AXI でプロセッサとつながる IP コアを作る」の第4回～第5回で使用したソースコードの一式が含まれています。

システムを構築するだけであれば、単にこのファイルのあるディレクトリを Vivado のプロジェクト設定で IP Repository に指定して、ブロック図の作成以降の手順を行うだけで済みます。

この IP コア単体のテストベンチを動作させるには、<a href="https://marsee101.blog.fc2.com/blog-entry-3509.html">marsee 氏作の AXI4 Slave BFM</a> が必要です。同ページ中の axi_slave_BFM.v および sync_fifo.v を、それぞれ testbench ディレクトリに追加してください。その上で、hdl ディレクトリの全てのファイルを Design Source(s)、testbench ディレクトリの全てのファイルを Simulation Source(s) に加えたプロジェクトを作成し、シミュレーションを行ってください。

詳細は、同コースの記事を確認してください。ACRi ブログへの掲載後に各記事へのリンクを追加します。

ディレクトリ構造は以下のとおりです。

- stencil: IP コア一式
  - hdl: 設計ファイル (Verilog HDL, SystemVerilog) 一式
  - testbench: テストベンチ (SystemVerilog)
  - xgui: GUI 設定画面の定義 (Vivado で自動生成)
  - component.xml: IP コアの定義 (Vivado で自動生成)
- stencil.c: 動作確認・性能比較を行うための C プログラム
- LICENSE.txt: ライセンス文
- README.md: このファイル